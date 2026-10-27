# WebP encoder — lossless VP8L bitstream (the `VP8L` chunk and the
# losslessly compressed `ALPH` chunk): `WebpEncoder::Lossless`.
module Hwaro
  module Content
    module Processors
      module WebpEncoder
        # LSB-first bit writer.
        class BitWriter
          @bytes = [] of UInt8
          @acc = 0_u64
          @used = 0

          def put(value : Int, nbits : Int32) : Nil
            return if nbits == 0
            @acc |= value.to_u64 << @used
            @used += nbits
            while @used >= 8
              @bytes << (@acc & 0xFF).to_u8
              @acc >>= 8
              @used -= 8
            end
          end

          def finish : Bytes
            @bytes << (@acc & 0xFF).to_u8 if @used > 0
            Slice.new(@bytes.to_unsafe, @bytes.size)
          end
        end

        # A canonical prefix code. A code with a single symbol takes no bits
        # at all: that is how the decoder builds it.
        class PrefixCode
          getter lengths : Array(Int32)
          @codes : Array(Int32)
          @single : Bool

          def initialize(@lengths : Array(Int32))
            @single = @lengths.count(&.> 0) <= 1
            @codes = canonical(@lengths)
          end

          def write(bw : BitWriter, symbol : Int32) : Nil
            bw.put(@codes[symbol], @lengths[symbol]) unless @single
          end

          # Bit-reversed canonical codes: VP8L reads a code's first bit
          # first, from the least significant end.
          private def canonical(lengths : Array(Int32)) : Array(Int32)
            max = lengths.max? || 0
            count = Array.new(max + 1, 0)
            lengths.each { |len| count[len] += 1 if len > 0 }
            next_code = Array.new(max + 2, 0)
            code = 0
            (1..max).each do |bits|
              code = (code + count[bits - 1]) << 1 if bits > 1
              next_code[bits] = code
            end
            lengths.map do |len|
              next 0 if len == 0
              c = next_code[len]
              next_code[len] += 1
              rev = 0
              len.times { |i| rev |= ((c >> i) & 1) << (len - 1 - i) }
              rev
            end
          end
        end

        module Lossless
          extend self

          # Code-length code symbols in the order their lengths are sent.
          CODE_LENGTH_ORDER = {17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
          MIN_MATCH         =    3
          MAX_MATCH         = 4096
          # Backward-reference search: hash-chain depth and window (pixels).
          CHAIN_DEPTH = 32
          WINDOW      = 1 << 18
          HASH_BITS   = 16

          # A `VP8L` chunk payload: header, subtract-green transform, one
          # prefix-code group.
          def encode(argb : Slice(UInt32), width : Int32, height : Int32, has_alpha : Bool) : Bytes
            bw = BitWriter.new
            bw.put(0x2f, 8)
            bw.put(width - 1, 14)
            bw.put(height - 1, 14)
            bw.put(has_alpha ? 1 : 0, 1)
            bw.put(0, 3) # version
            bw.put(1, 1) # transform: subtract green
            bw.put(2, 2)
            pixels = argb.map do |px|
              g = (px >> 8) & 0xFF
              r = ((px >> 16) &- g) & 0xFF
              b = (px &- g) & 0xFF
              (px & 0xFF00FF00_u32) | (r << 16) | b
            end
            write_image(bw, pixels, width)
            bw.finish
          end

          # An `ALPH` chunk payload: the alpha plane, through whichever
          # prediction filter (none, horizontal, vertical, gradient) codes
          # smallest, as the green channel of a header-less VP8L stream.
          def encode_alpha(alpha : Bytes, width : Int32, height : Int32) : Bytes
            best = Bytes.empty
            4.times do |filter|
              filtered = filter_alpha(alpha, width, height, filter)
              bw = BitWriter.new
              write_image(bw, Slice(UInt32).new(filtered.size) { |i| filtered[i].to_u32 << 8 }, width)
              data = bw.finish
              next unless best.empty? || data.size + 1 < best.size
              best = Bytes.new(data.size + 1)
              best[0] = (filter << 2 | 1).to_u8 # filter, lossless compression
              best[1, data.size].copy_from(data)
            end
            best
          end

          # Residuals against the decoder's alpha unfilter predictors.
          private def filter_alpha(alpha : Bytes, width : Int32, height : Int32, filter : Int32) : Bytes
            return alpha if filter == 0
            Bytes.new(alpha.size) do |idx|
              y, x = idx.divmod(width)
              pred = if y == 0
                       x == 0 ? 0 : alpha[idx - 1].to_i32
                     elsif x == 0
                       alpha[idx - width].to_i32
                     else
                       case filter
                       when 1 then alpha[idx - 1].to_i32
                       when 2 then alpha[idx - width].to_i32
                       else        (alpha[idx - 1].to_i32 + alpha[idx - width] - alpha[idx - width - 1]).clamp(0, 255)
                       end
                     end
              ((alpha[idx].to_i32 - pred) & 0xFF).to_u8
            end
          end

          # The rest of an image stream after its transforms: no more
          # transforms, no colour cache, one prefix-code group, then the
          # LZ77-coded pixels.
          private def write_image(bw : BitWriter, pixels : Slice(UInt32), width : Int32) : Nil
            bw.put(0, 1) # end of transforms
            bw.put(0, 1) # no colour cache
            bw.put(0, 1) # no meta prefix codes
            tokens = backward_refs(pixels, width)

            green = Array.new(256 + 24, 0)
            red = Array.new(256, 0)
            blue = Array.new(256, 0)
            alpha = Array.new(256, 0)
            dist = Array.new(40, 0)
            tokens.each do |t|
              if t.copy?
                green[256 + prefix(t.length)[0]] += 1
                dist[prefix(t.distance)[0]] += 1
              else
                px = t.pixel
                green[(px >> 8) & 0xFF] += 1
                red[(px >> 16) & 0xFF] += 1
                blue[px & 0xFF] += 1
                alpha[px >> 24] += 1
              end
            end
            codes = {green, red, blue, alpha, dist}.map do |freq|
              code = PrefixCode.new(huffman_lengths(freq, 15))
              write_code(bw, code)
              code
            end

            tokens.each do |t|
              if t.copy?
                sym, extra, bits = prefix(t.length)
                codes[0].write(bw, 256 + sym)
                bw.put(extra, bits)
                sym, extra, bits = prefix(t.distance)
                codes[4].write(bw, sym)
                bw.put(extra, bits)
              else
                px = t.pixel
                codes[0].write(bw, ((px >> 8) & 0xFF).to_i32)
                codes[1].write(bw, ((px >> 16) & 0xFF).to_i32)
                codes[2].write(bw, (px & 0xFF).to_i32)
                codes[3].write(bw, (px >> 24).to_i32)
              end
            end
          end

          # A literal pixel, or a copy of `length` pixels from `distance`
          # (already a plane code) back.
          record Token, pixel : UInt32, length : Int32, distance : Int32 do
            def copy? : Bool
              length > 0
            end
          end

          # Greedy LZ77 over pixels with a hash chain; the pixel above and
          # the one to the left are always tried, and get the two shortest
          # distance codes.
          private def backward_refs(pixels : Slice(UInt32), width : Int32) : Array(Token)
            n = pixels.size
            head = Slice(Int32).new(1 << HASH_BITS, -1)
            chain = Slice(Int32).new(n, -1)
            tokens = [] of Token
            insert = ->(at : Int32) do
              return if at + 1 >= n
              h = hash(pixels[at], pixels[at + 1])
              chain[at] = head[h]
              head[h] = at
            end
            i = 0
            while i < n
              best_len = 0
              best_dist = 0
              limit = Math.min(MAX_MATCH, n - i)
              if limit >= MIN_MATCH
                consider = ->(dist : Int32) do
                  len = match_length(pixels, i - dist, i, limit)
                  if len > best_len
                    best_len = len
                    best_dist = dist
                  end
                end
                consider.call(1) if i >= 1
                consider.call(width) if i >= width && width > 1
                cand = head[hash(pixels[i], pixels[i + 1])]
                depth = 0
                while cand >= 0 && i - cand <= WINDOW && depth < CHAIN_DEPTH && best_len < limit
                  consider.call(i - cand)
                  cand = chain[cand]
                  depth += 1
                end
              end
              if best_len >= MIN_MATCH
                tokens << Token.new(0_u32, best_len, plane_code(best_dist, width))
                best_len.times { |k| insert.call(i + k) }
                i += best_len
              else
                tokens << Token.new(pixels[i], 0, 0)
                insert.call(i)
                i += 1
              end
            end
            tokens
          end

          private def hash(a : UInt32, b : UInt32) : Int32
            ((a &* 0x1e35a7bd_u32 &+ b &* 0x9e3779b1_u32) >> (32 - HASH_BITS)).to_i32
          end

          private def match_length(pixels : Slice(UInt32), from : Int32, at : Int32, limit : Int32) : Int32
            len = 0
            while len < limit && pixels[from + len] == pixels[at + len]
              len += 1
            end
            len
          end

          # Distance as a VP8L plane code: 1 is the pixel above, 2 the pixel
          # to the left, anything else the distance plus 120.
          private def plane_code(dist : Int32, width : Int32) : Int32
            return 1 if dist == width
            return 2 if dist == 1
            dist + 120
          end

          # Prefix coding of a length or distance value (>= 1):
          # {symbol, extra bits value, extra bit count}.
          private def prefix(value : Int32) : {Int32, Int32, Int32}
            v = value - 1
            return {v, 0, 0} if v < 4
            high = 31 - v.leading_zeros_count
            second = (v >> (high - 1)) & 1
            extra = high - 1
            {2 * high + second, v & ((1 << extra) - 1), extra}
          end

          # Write a prefix code's lengths: the 1-2 symbol "simple" form when
          # it fits, else run-length coded through a code-length code.
          private def write_code(bw : BitWriter, code : PrefixCode) : Nil
            lengths = code.lengths
            used = (0...lengths.size).select { |s| lengths[s] > 0 }
            if used.empty? || (used.size <= 2 && used.all? { |s| s < 256 })
              symbols = used.empty? ? [0] : used
              bw.put(1, 1)
              bw.put(symbols.size - 1, 1)
              if symbols[0] < 2
                bw.put(0, 1)
                bw.put(symbols[0], 1)
              else
                bw.put(1, 1)
                bw.put(symbols[0], 8)
              end
              bw.put(symbols[1], 8) if symbols.size == 2
              return
            end

            tokens = rle(lengths)
            freq = Array.new(19, 0)
            tokens.each { |(sym, _, _)| freq[sym] += 1 }
            cl_code = PrefixCode.new(huffman_lengths(freq, 7))
            count = 19
            while count > 4 && cl_code.lengths[CODE_LENGTH_ORDER[count - 1]] == 0
              count -= 1
            end
            bw.put(0, 1)
            bw.put(count - 4, 4)
            count.times { |i| bw.put(cl_code.lengths[CODE_LENGTH_ORDER[i]], 3) }
            bw.put(0, 1) # lengths for the whole alphabet
            tokens.each do |(sym, extra, bits)|
              cl_code.write(bw, sym)
              bw.put(extra, bits)
            end
          end

          # Code lengths as code-length symbols: 0-15 literal, 16 repeats
          # the previous length 3-6 times, 17/18 run 3-10/11-138 zeros.
          private def rle(lengths : Array(Int32)) : Array({Int32, Int32, Int32})
            res = [] of {Int32, Int32, Int32}
            i = 0
            while i < lengths.size
              v = lengths[i]
              run = 1
              while i + run < lengths.size && lengths[i + run] == v
                run += 1
              end
              left = run
              if v == 0
                while left > 0
                  if left < 3
                    left.times { res << {0, 0, 0} }
                    left = 0
                  elsif left <= 10
                    res << {17, left - 3, 3}
                    left = 0
                  else
                    k = Math.min(left, 138)
                    res << {18, k - 11, 7}
                    left -= k
                  end
                end
              else
                res << {v, 0, 0}
                left -= 1
                while left > 0
                  if left < 3
                    left.times { res << {v, 0, 0} }
                    left = 0
                  else
                    k = Math.min(left, 6)
                    res << {16, k - 3, 2}
                    left -= k
                  end
                end
              end
              i += run
            end
            res
          end

          # Huffman code lengths no longer than `limit`: an over-long tree
          # is rebuilt with rare symbols' counts raised until it fits
          # (libwebp's approach). A lone symbol gets length 1.
          def huffman_lengths(freq : Array(Int32), limit : Int32) : Array(Int32)
            lengths = Array.new(freq.size, 0)
            used = (0...freq.size).select { |s| freq[s] > 0 }
            return lengths if used.empty?
            if used.size == 1
              lengths[used[0]] = 1
              return lengths
            end
            floor = 1_i64
            loop do
              leaves = used.map { |s| {Math.max(freq[s].to_i64, floor), s} }.sort!
              m = leaves.size
              weight = Array(Int64).new(2 * m - 1, 0_i64)
              parent = Array(Int32).new(2 * m - 1, -1)
              m.times { |k| weight[k] = leaves[k][0] }
              li = 0
              ii = m
              (m...2 * m - 1).each do |node|
                pair = StaticArray(Int32, 2).new do
                  if li < m && (ii >= node || weight[li] <= weight[ii])
                    li += 1
                    li - 1
                  else
                    ii += 1
                    ii - 1
                  end
                end
                weight[node] = weight[pair[0]] + weight[pair[1]]
                parent[pair[0]] = parent[pair[1]] = node
              end
              depth = Array(Int32).new(2 * m - 1, 0)
              (2 * m - 3).downto(0) { |k| depth[k] = depth[parent[k]] + 1 }
              if (0...m).all? { |k| depth[k] <= limit }
                m.times { |k| lengths[leaves[k][1]] = depth[k] }
                return lengths
              end
              floor *= 2
            end
          end
        end
      end
    end
  end
end
