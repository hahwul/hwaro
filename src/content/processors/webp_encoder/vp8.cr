# WebP encoder — lossy VP8 key frame (RFC 6386): `WebpEncoder::VP8` with its
# boolean entropy coder and quantizer.
module Hwaro
  module Content
    module Processors
      module WebpEncoder
        # VP8 boolean entropy coder (RFC 6386 §7.3).
        class BoolWriter
          @bytes = [] of UInt8
          @range = 255_u32
          @bottom = 0_u32
          @bit_count = 24

          # Code `bit`, where `prob`/256 is the probability of a 0.
          def put(bit : Bool, prob : Int32) : Nil
            split = 1_u32 &+ (((@range &- 1) &* prob.to_u32) >> 8)
            if bit
              @bottom &+= split
              @range &-= split
            else
              @range = split
            end
            while @range < 128
              @range <<= 1
              carry if @bottom & 0x8000_0000_u32 != 0
              @bottom <<= 1
              @bit_count -= 1
              if @bit_count == 0
                @bytes << (@bottom >> 24).to_u8
                @bottom &= 0xFF_FFFF_u32
                @bit_count = 8
              end
            end
          end

          # `nbits` of `value`, most significant first, at even odds.
          def put_literal(value : Int32, nbits : Int32) : Nil
            (nbits - 1).downto(0) { |i| put((value >> i) & 1 == 1, 128) }
          end

          # The header's optional quantizer deltas: a presence flag, then
          # magnitude and sign.
          def put_signed(value : Int32, nbits : Int32) : Nil
            put(value != 0, 128)
            return if value == 0
            put_literal(value.abs, nbits)
            put(value < 0, 128)
          end

          def finish : Bytes
            c = @bit_count
            v = @bottom
            carry if v & (1_u32 << (32 - c)) != 0
            v <<= (c & 7)
            (c >> 3).times { v <<= 8 }
            4.times do
              @bytes << (v >> 24).to_u8
              v <<= 8
            end
            Slice.new(@bytes.to_unsafe, @bytes.size)
          end

          private def carry : Nil
            i = @bytes.size - 1
            while i >= 0 && @bytes[i] == 255
              @bytes[i] = 0
              i -= 1
            end
            @bytes[i] += 1 if i >= 0
          end
        end

        # One quantizer (RFC 6386 §14.1 steps) with libwebp's rounding bias
        # and the dead-zone threshold derived from it, for the DC (index 0)
        # and AC (index 1) positions.
        class Quantizer
          MAX_LEVEL = 2047
          # Slight boost of the high-frequency luma coefficients (libwebp's
          # kFreqSharpening, in raster order).
          SHARPEN = Slice[0, 30, 60, 90, 30, 60, 90, 90, 60, 90, 90, 90, 90, 90, 90, 90]

          # Per zigzag position: raster index, step, reciprocal, bias,
          # dead-zone threshold and sharpening boost.
          @raster = StaticArray(Int32, 16).new(0)
          @step = StaticArray(Int32, 16).new(0)
          @iq = StaticArray(Int32, 16).new(0)
          @bias = StaticArray(Int32, 16).new(0)
          @zthresh = StaticArray(Int32, 16).new(0)
          @boost = StaticArray(Int32, 16).new(0)

          def initialize(q : {Int32, Int32}, bias : {Int32, Int32}, sharpen : Bool)
            16.times do |n|
              i = n == 0 ? 0 : 1
              j = ZIGZAG[n]
              @raster[n] = j
              @step[n] = q[i]
              @iq[n] = (1 << 17) // q[i]
              @bias[n] = bias[i] << 9
              @zthresh[n] = ((1 << 17) - 1 - @bias[n]) // @iq[n]
              @boost[n] = sharpen ? (SHARPEN[j] * q[i]) >> 11 : 0
            end
          end

          # Quantize the raster-order block at `coeffs[off]` from zigzag
          # position `first`: levels go to `levels[loff]` in zigzag order and
          # `coeffs` is replaced by what the decoder will dequantize.
          def quantize(coeffs : Slice(Int32), off : Int32, first : Int32, levels : Slice(Int16), loff : Int32) : Nil
            c = coeffs[off, 16].to_unsafe
            lv = levels[loff, 16].to_unsafe
            lv[0] = 0 if first > 0
            n = first
            while n < 16
              j = @raster.unsafe_fetch(n)
              v = c[j]
              a = v.abs + @boost.unsafe_fetch(n)
              if a > @zthresh.unsafe_fetch(n)
                level = Math.min(((a.to_i64 * @iq.unsafe_fetch(n) + @bias.unsafe_fetch(n)) >> 17).to_i32, MAX_LEVEL)
                level = -level if v < 0
                c[j] = level * @step.unsafe_fetch(n)
                lv[n] = level.to_i16
              else
                c[j] = 0
                lv[n] = 0
              end
              n += 1
            end
          end
        end

        class VP8
          # Work-buffer stride and the index of a macroblock's top-left pixel
          # in it: one row above and room on the left for the edge samples,
          # the layout the libwebp decoder predicts in.
          BPS   = 32
          Y_OFF = BPS + 8

          # Quantizer bias (1/256 of a step) for [dc, ac] of luma, the Y2
          # block (the luma DCs of an intra 16x16 macroblock) and chroma.
          BIAS_Y1 = {96, 110}
          BIAS_Y2 = {96, 108}
          BIAS_UV = {110, 115}
          # Chroma DC quantizer offset libwebp writes at its default settings.
          UV_DC_DELTA = -2
          # Rate-distortion weight: lambda = K * (AC step)^2, distortion in
          # squared error, rate in bits.
          LAMBDA_K    = 0.023
          LAMBDA_UV_K = 0.047

          # Sub-block modes fully evaluated per 4x4 block (of 10).
          I4_CANDIDATES = 3

          # Coefficient table types.
          TYPE_I16_AC = 0
          TYPE_Y2     = 1
          TYPE_UV     = 2
          TYPE_I4     = 3

          # Per macroblock: block 0 = Y2, 1-16 = Y, 17-20 = U, 21-24 = V.
          LEVELS_PER_MB = 25 * 16

          # Partition 0 length is a 19-bit field of the frame tag.
          MAX_PARTITION0 = (1 << 19) - 1

          @mb_w : Int32
          @mb_h : Int32
          @yw : Int32
          @uvw : Int32
          @src_y : Bytes
          @src_u : Bytes
          @src_v : Bytes
          @rec_y : Bytes
          @rec_u : Bytes
          @rec_v : Bytes
          @q_index : Int32
          @y1 : Quantizer
          @y2 : Quantizer
          @uv : Quantizer
          @lambda : Int64
          @lambda_uv : Int64

          # Per macroblock decisions and quantized levels.
          @levels : Slice(Int16)
          @is_i4 : Slice(Bool)
          @y_mode : Slice(UInt8)
          @i4_modes : Bytes
          @uv_mode : Slice(UInt8)
          @skip : Slice(Bool)

          # Context while choosing modes: non-zero flags (bits 0-3 luma
          # columns/rows, 4-5 U, 6-7 V), Y2 non-zero flag, sub-block modes.
          @top_nz : Slice(Int32)
          @top_nz_dc : Slice(Int32)
          @left_nz = 0
          @left_nz_dc = 0
          @top_modes : Bytes
          @left_modes = Bytes.new(4)

          # Default-probability bit costs per coefficient slot, and the band
          # of each coefficient position (constants, copied for the hot path).
          @cost0 = Slice(Int32).new(COEFF_PROBS.size) { |i| COST[COEFF_PROBS[i]] }
          @cost1 = Slice(Int32).new(COEFF_PROBS.size) { |i| COST[256 - COEFF_PROBS[i]] }
          @bands = StaticArray(Int32, 17).new { |i| BANDS[i] }

          # Scratch.
          @yb = Bytes.new(BPS * 18)
          @ub = Bytes.new(BPS * 10)
          @vb = Bytes.new(BPS * 10)
          @pred16 = Bytes.new(256)
          @pred4s = Bytes.new(160)
          @pred_u = Bytes.new(64)
          @pred_v = Bytes.new(64)
          @coef = Slice(Int32).new(256)
          @c4 = Slice(Int32).new(16)
          @dc = Slice(Int32).new(16)
          @y2c = Slice(Int32).new(16)
          @lv4 = Slice(Int16).new(16)
          @rec4 = Bytes.new(16)
          @best_rec4 = Bytes.new(16)
          @cand16 = Slice(Int16).new(17 * 16)
          @best16 = Slice(Int16).new(17 * 16)
          @lv_i4 = Slice(Int16).new(17 * 16)
          @cand_rec16 = Bytes.new(256)
          @best_rec16 = Bytes.new(256)
          @modes4 = Bytes.new(16)
          @cand_uv = Slice(Int16).new(8 * 16)
          @best_uv = Slice(Int16).new(8 * 16)
          @cand_rec_u = Bytes.new(64)
          @cand_rec_v = Bytes.new(64)
          @best_rec_u = Bytes.new(64)
          @best_rec_v = Bytes.new(64)

          def initialize(pixels : Bytes, @width : Int32, @height : Int32, channels : Int32, quality : Int32)
            @mb_w = (@width + 15) // 16
            @mb_h = (@height + 15) // 16
            @yw = @mb_w * 16
            @uvw = @mb_w * 8
            @src_y, @src_u, @src_v = to_yuv(pixels, channels)
            @rec_y = Bytes.new(@src_y.size)
            @rec_u = Bytes.new(@src_u.size)
            @rec_v = Bytes.new(@src_v.size)

            @q_index = quality_to_q(quality)
            q = @q_index
            uv_dc = (q + UV_DC_DELTA).clamp(0, 117)
            y2_ac = Math.max((AC_TABLE[q] * 101581) >> 16, 8)
            @y1 = Quantizer.new({DC_TABLE[q], AC_TABLE[q]}, BIAS_Y1, true)
            @y2 = Quantizer.new({DC_TABLE[q] * 2, y2_ac}, BIAS_Y2, false)
            @uv = Quantizer.new({DC_TABLE[uv_dc], AC_TABLE[q]}, BIAS_UV, false)
            @lambda = Math.max((LAMBDA_K * AC_TABLE[q] ** 2).round.to_i64, 1_i64)
            @lambda_uv = Math.max((LAMBDA_UV_K * AC_TABLE[q] ** 2).round.to_i64, 1_i64)

            count = @mb_w * @mb_h
            @levels = Slice(Int16).new(count * LEVELS_PER_MB)
            @is_i4 = Slice(Bool).new(count, false)
            @y_mode = Slice(UInt8).new(count)
            @i4_modes = Bytes.new(count * 16)
            @uv_mode = Slice(UInt8).new(count)
            @skip = Slice(Bool).new(count, false)
            @top_nz = Slice(Int32).new(@mb_w, 0)
            @top_nz_dc = Slice(Int32).new(@mb_w, 0)
            @top_modes = Bytes.new(@mb_w * 4)
          end

          # The VP8 frame (the "VP8 " chunk payload), or nil when partition 0
          # outgrows its size field.
          def encode : Bytes?
            @mb_h.times do |mby|
              @left_nz = 0
              @left_nz_dc = 0
              @left_modes.fill(0_u8)
              @mb_w.times { |mbx| encode_mb(mbx, mby) }
            end
            write_frame
          end

          # libwebp's quality -> quantizer index curve (file size grows
          # roughly with the cube of the quantizer).
          private def quality_to_q(quality : Int32) : Int32
            c = quality / 100.0
            linear = c < 0.75 ? c * 2.0 / 3.0 : 2.0 * c - 1.0
            (127.0 * (1.0 - linear ** (1.0 / 3.0))).to_i.clamp(0, 127)
          end

          # BT.601 YUV 4:2:0 (libwebp's fixed-point coefficients), padded to
          # whole macroblocks by repeating the last column/row.
          private def to_yuv(pixels : Bytes, channels : Int32) : {Bytes, Bytes, Bytes}
            y = Bytes.new(@yw * @mb_h * 16)
            u = Bytes.new(@uvw * @mb_h * 8)
            v = Bytes.new(@uvw * @mb_h * 8)
            rgb = ->(px : Int32, py : Int32) do
              p = (Math.min(py, @height - 1) * @width + Math.min(px, @width - 1)) * channels
              channels >= 3 ? {pixels[p].to_i32, pixels[p + 1].to_i32, pixels[p + 2].to_i32} : {pixels[p].to_i32, pixels[p].to_i32, pixels[p].to_i32}
            end
            (@mb_h * 16).times do |py|
              @yw.times do |px|
                r, g, b = rgb.call(px, py)
                y[py * @yw + px] = ((16839 * r + 33059 * g + 6420 * b + (1 << 15) + (16 << 16)) >> 16).to_u8
              end
            end
            (@mb_h * 8).times do |cy|
              @uvw.times do |cx|
                r = g = b = 0
                {0, 1}.each do |dy|
                  {0, 1}.each do |dx|
                    pr, pg, pb = rgb.call(cx * 2 + dx, cy * 2 + dy)
                    r += pr
                    g += pg
                    b += pb
                  end
                end
                u[cy * @uvw + cx] = clip_uv(-9719 * r - 19081 * g + 28800 * b)
                v[cy * @uvw + cx] = clip_uv(28800 * r - 24116 * g - 4684 * b)
              end
            end
            {y, u, v}
          end

          private def clip_uv(value : Int32) : UInt8
            ((value + (1 << 17) + (128 << 18)) >> 18).clamp(0, 255).to_u8
          end

          # --- Macroblock analysis -----------------------------------------

          private def encode_mb(mbx : Int32, mby : Int32) : Nil
            load_context(mbx, mby)
            mb = mby * @mb_w + mbx
            src_off = mby * 16 * @yw + mbx * 16

            best16 = Int64::MAX
            best_mode = 0
            4.times do |mode|
              predict16(check_mode(mbx, mby, mode), @yb, Y_OFF, @pred16)
              score = trial16(src_off, mbx, mode)
              next unless score < best16
              best16 = score
              best_mode = mode
              @cand16, @best16 = @best16, @cand16
              @cand_rec16, @best_rec16 = @best_rec16, @cand_rec16
            end

            i4 = trial4(src_off, mbx, best16) < best16
            levels = i4 ? @lv_i4 : @best16
            @is_i4[mb] = i4
            @y_mode[mb] = best_mode.to_u8
            lv = mb * LEVELS_PER_MB
            levels.copy_to(@levels[lv, 17 * 16])
            @levels[lv, 16].fill(0_i16) if i4
            16.times do |row|
              dst = (mby * 16 + row) * @yw + mbx * 16
              if i4
                @rec_y[dst, 16].copy_from(@yb[Y_OFF + row * BPS, 16])
              else
                @rec_y[dst, 16].copy_from(@best_rec16[row * 16, 16])
              end
            end
            ynz = luma_nz(lv, i4 ? 0 : 1)
            @top_nz[mbx] = (@top_nz[mbx] & ~0xF) | (ynz >> 12)
            @left_nz = (@left_nz & ~0xF) | column3(ynz)
            if i4
              @i4_modes[mb * 16, 16].copy_from(@modes4)
              4.times do |k|
                @top_modes[mbx * 4 + k] = @modes4[12 + k]
                @left_modes[k] = @modes4[k * 4 + 3]
              end
            else
              nz_dc = nz?(@levels, lv, 0) ? 1 : 0
              @top_nz_dc[mbx] = @left_nz_dc = nz_dc
              @top_modes[mbx * 4, 4].fill(best_mode.to_u8)
              @left_modes.fill(best_mode.to_u8)
            end

            encode_uv(mbx, mby, mb, lv)
            @skip[mb] = (i4 ? 16 : 0).upto(25 * 16 - 1).all? { |i| @levels[lv + i] == 0 }
          end

          # Score of intra 16x16 `mode` (prediction already in @pred16):
          # levels into @cand16, reconstruction into @cand_rec16.
          private def trial16(src_off : Int32, mbx : Int32, mode : Int32) : Int64
            16.times do |n|
              bx = (n & 3) * 4
              by = (n >> 2) * 4
              ftransform(@src_y, src_off + by * @yw + bx, @yw, @pred16, by * 16 + bx, 16, @coef, n * 16)
              @dc[n] = @coef[n * 16]
            end
            fwht(@dc, @y2c)
            @y2.quantize(@y2c, 0, 0, @cand16, 0)
            rate = block_cost(@cand16, 0, 0, TYPE_Y2, @top_nz_dc[mbx] + @left_nz_dc)[0]
            iwht(@y2c, @dc)
            tnz = @top_nz[mbx] & 0xF
            lnz = @left_nz & 0xF
            16.times do |n|
              x = n & 3
              y = n >> 2
              @y1.quantize(@coef, n * 16, 1, @cand16, (1 + n) * 16)
              cost, nz = block_cost(@cand16, (1 + n) * 16, 1, TYPE_I16_AC, ((tnz >> x) & 1) + ((lnz >> y) & 1))
              rate += cost
              tnz = nz ? tnz | (1 << x) : tnz & ~(1 << x)
              lnz = nz ? lnz | (1 << y) : lnz & ~(1 << y)
              @coef[n * 16] = @dc[n]
              off = y * 4 * 16 + x * 4
              itransform(@coef, n * 16, @pred16, off, 16, @cand_rec16, off, 16)
            end
            i16_mode_bits(mode) { |bit, prob| rate += bit_cost(bit, prob) }
            sse(@src_y, src_off, @yw, @cand_rec16, 0, 16, 16) * 256 + @lambda * rate
          end

          # Score of intra 4x4, reconstructing into @yb's interior and
          # leaving levels in @lv_i4 and modes in @modes4. Stops early once
          # it cannot beat `budget`.
          private def trial4(src_off : Int32, mbx : Int32, budget : Int64) : Int64
            score = @lambda * COST[145]
            tnz = @top_nz[mbx] & 0xF
            lnz = @left_nz & 0xF
            top = StaticArray(Int32, 4).new { |k| @top_modes[mbx * 4 + k].to_i32 }
            left = StaticArray(Int32, 4).new { |k| @left_modes[k].to_i32 }
            16.times do |n|
              x = n & 3
              y = n >> 2
              base = Y_OFF + y * 4 * BPS + x * 4
              soff = src_off + y * 4 * @yw + x * 4
              ctx = ((tnz >> x) & 1) + ((lnz >> y) & 1)
              best = Int64::MAX
              best_mode = 0
              best_nz = false
              mode_costs = I4_MODE_COSTS[(top[x] * 10 + left[y]) * 10, 10]
              # Rank the ten predictions by prediction error first; only the
              # most promising few are transformed, quantized and costed.
              picks = StaticArray(Int32, I4_CANDIDATES).new(-1)
              pick_scores = StaticArray(Int64, I4_CANDIDATES).new(Int64::MAX)
              10.times do |mode|
                predict4(mode, @yb, base, @pred4s[mode * 16, 16])
                s = sse(@src_y, soff, @yw, @pred4s, mode * 16, 4, 4) * 256 + @lambda * mode_costs[mode]
                next unless s < pick_scores[I4_CANDIDATES - 1]
                k = I4_CANDIDATES - 1
                while k > 0 && pick_scores[k - 1] > s
                  picks[k] = picks[k - 1]
                  pick_scores[k] = pick_scores[k - 1]
                  k -= 1
                end
                picks[k] = mode
                pick_scores[k] = s
              end
              picks.each do |mode|
                pred = @pred4s[mode * 16, 16]
                ftransform(@src_y, soff, @yw, pred, 0, 4, @c4, 0)
                @y1.quantize(@c4, 0, 0, @lv4, 0)
                itransform(@c4, 0, pred, 0, 4, @rec4, 0, 4)
                cost, nz = block_cost(@lv4, 0, 0, TYPE_I4, ctx)
                cost += mode_costs[mode]
                s = sse(@src_y, soff, @yw, @rec4, 0, 4, 4) * 256 + @lambda * cost
                next unless s < best
                best = s
                best_mode = mode
                best_nz = nz
                @lv4.copy_to(@lv_i4[(1 + n) * 16, 16])
                @rec4.copy_to(@best_rec4)
              end
              4.times { |r| @yb[base + r * BPS, 4].copy_from(@best_rec4[r * 4, 4]) }
              @modes4[n] = best_mode.to_u8
              top[x] = left[y] = best_mode
              tnz = best_nz ? tnz | (1 << x) : tnz & ~(1 << x)
              lnz = best_nz ? lnz | (1 << y) : lnz & ~(1 << y)
              score += best
              return score if score >= budget
            end
            score
          end

          private def encode_uv(mbx : Int32, mby : Int32, mb : Int32, lv : Int32) : Nil
            src_off = mby * 8 * @uvw + mbx * 8
            best = Int64::MAX
            best_mode = 0
            4.times do |mode|
              pm = check_mode(mbx, mby, mode)
              predict8(pm, @ub, Y_OFF, @pred_u)
              predict8(pm, @vb, Y_OFF, @pred_v)
              score = trial_uv(src_off, mbx, mode)
              next unless score < best
              best = score
              best_mode = mode
              @cand_uv, @best_uv = @best_uv, @cand_uv
              @cand_rec_u, @best_rec_u = @best_rec_u, @cand_rec_u
              @cand_rec_v, @best_rec_v = @best_rec_v, @cand_rec_v
            end
            @uv_mode[mb] = best_mode.to_u8
            @best_uv.copy_to(@levels[lv + 17 * 16, 8 * 16])
            8.times do |row|
              dst = (mby * 8 + row) * @uvw + mbx * 8
              @rec_u[dst, 8].copy_from(@best_rec_u[row * 8, 8])
              @rec_v[dst, 8].copy_from(@best_rec_v[row * 8, 8])
            end
            tnz = 0
            lnz = 0
            8.times do |k|
              next unless nz?(@levels, lv + (17 + k) * 16, 0)
              ch = k >> 2
              x = k & 1
              y = (k >> 1) & 1
              tnz |= 1 << (ch * 2 + x) if y == 1
              lnz |= 1 << (ch * 2 + y) if x == 1
            end
            @top_nz[mbx] = (@top_nz[mbx] & 0xF) | (tnz << 4)
            @left_nz = (@left_nz & 0xF) | (lnz << 4)
          end

          private def trial_uv(src_off : Int32, mbx : Int32, mode : Int32) : Int64
            tnz = (@top_nz[mbx] >> 4) & 0xF
            lnz = (@left_nz >> 4) & 0xF
            rate = 0_i64
            uv_mode_bits(mode) { |bit, prob| rate += bit_cost(bit, prob) }
            dist = 0_i64
            2.times do |ch|
              src = ch == 0 ? @src_u : @src_v
              pred = ch == 0 ? @pred_u : @pred_v
              rec = ch == 0 ? @cand_rec_u : @cand_rec_v
              4.times do |k|
                x = k & 1
                y = k >> 1
                poff = y * 4 * 8 + x * 4
                ftransform(src, src_off + y * 4 * @uvw + x * 4, @uvw, pred, poff, 8, @c4, 0)
                @uv.quantize(@c4, 0, 0, @cand_uv, (ch * 4 + k) * 16)
                cost, nz = block_cost(@cand_uv, (ch * 4 + k) * 16, 0, TYPE_UV, ((tnz >> (ch * 2 + x)) & 1) + ((lnz >> (ch * 2 + y)) & 1))
                rate += cost
                tbit = 1 << (ch * 2 + x)
                lbit = 1 << (ch * 2 + y)
                tnz = nz ? tnz | tbit : tnz & ~tbit
                lnz = nz ? lnz | lbit : lnz & ~lbit
                itransform(@c4, 0, pred, poff, 8, rec, poff, 8)
              end
              dist += sse(src, src_off, @uvw, rec, 0, 8, 8)
            end
            dist * 256 + @lambda_uv * rate
          end

          # Non-zero flags of the 16 luma blocks of macroblock `lv`, bit n
          # for block n (raster order).
          private def luma_nz(lv : Int32, first : Int32) : Int32
            bits = 0
            16.times { |n| bits |= 1 << n if nz?(@levels, lv + (1 + n) * 16, first) }
            bits
          end

          # Bits of the right-hand column (blocks 3, 7, 11, 15) as rows 0-3.
          private def column3(bits : Int32) : Int32
            ((bits >> 3) & 1) | ((bits >> 6) & 2) | ((bits >> 9) & 4) | ((bits >> 12) & 8)
          end

          private def nz?(levels : Slice(Int16), off : Int32, first : Int32) : Bool
            first.upto(15).any? { |i| levels[off + i] != 0 }
          end

          # Fill the work buffers' edges exactly as the decoder does before
          # predicting this macroblock: the reconstructed row above (127 on
          # the first row), the column to the left (129 on the first column),
          # and for luma the four pixels above-right, repeated down the right
          # edge for the sub-blocks of column 3.
          private def load_context(mbx : Int32, mby : Int32) : Nil
            load_plane_context(@yb, @rec_y, @yw, 16, mbx, mby)
            load_plane_context(@ub, @rec_u, @uvw, 8, mbx, mby)
            load_plane_context(@vb, @rec_v, @uvw, 8, mbx, mby)
            top = Y_OFF - BPS
            if mby == 0
              4.times { |i| @yb[top + 16 + i] = 127 }
            else
              row = (mby * 16 - 1) * @yw + mbx * 16
              4.times { |i| @yb[top + 16 + i] = mbx < @mb_w - 1 ? @rec_y[row + 16 + i] : @rec_y[row + 15] }
            end
            {3, 7, 11}.each { |r| 4.times { |i| @yb[Y_OFF + r * BPS + 16 + i] = @yb[top + 16 + i] } }
          end

          private def load_plane_context(buf : Bytes, rec : Bytes, stride : Int32, size : Int32, mbx : Int32, mby : Int32) : Nil
            top = Y_OFF - BPS
            x0 = mbx * size
            y0 = mby * size
            if mby == 0
              (-1...size).each { |i| buf[top + i] = 127 }
            else
              size.times { |i| buf[top + i] = rec[(y0 - 1) * stride + x0 + i] }
              buf[top - 1] = mbx == 0 ? 129_u8 : rec[(y0 - 1) * stride + x0 - 1]
            end
            size.times { |j| buf[Y_OFF - 1 + j * BPS] = mbx == 0 ? 129_u8 : rec[(y0 + j) * stride + x0 - 1] }
          end

          # The DC predictor's edge variants (the decoder's CheckMode): no
          # top row (4), no left column (5), neither (6).
          private def check_mode(mbx : Int32, mby : Int32, mode : Int32) : Int32
            return mode unless mode == 0
            mbx == 0 ? (mby == 0 ? 6 : 5) : (mby == 0 ? 4 : 0)
          end

          # --- Prediction (libwebp dsp/dec.c, writing into `out`) ----------

          private def predict16(mode : Int32, buf : Bytes, base : Int32, res : Bytes) : Nil
            predict_square(mode, buf, base, res, 16)
          end

          private def predict8(mode : Int32, buf : Bytes, base : Int32, res : Bytes) : Nil
            predict_square(mode, buf, base, res, 8)
          end

          # Modes 0 DC, 1 TM, 2 V, 3 H and the DC edge variants 4-6.
          private def predict_square(mode : Int32, buf : Bytes, base : Int32, res : Bytes, size : Int32) : Nil
            top = base - BPS
            shift = size == 16 ? 4 : 3
            case mode
            when 0
              dc = size
              size.times { |j| dc += buf[base - 1 + j * BPS].to_i32 + buf[top + j] }
              res.fill((dc >> (shift + 1)).to_u8)
            when 4
              dc = size >> 1
              size.times { |j| dc += buf[base - 1 + j * BPS] }
              res.fill((dc >> shift).to_u8)
            when 5
              dc = size >> 1
              size.times { |j| dc += buf[top + j] }
              res.fill((dc >> shift).to_u8)
            when 6
              res.fill(128_u8)
            when 1
              tl = buf[top - 1].to_i32
              size.times do |y|
                l = buf[base - 1 + y * BPS].to_i32 - tl
                size.times { |x| res[y * size + x] = (l + buf[top + x]).clamp(0, 255).to_u8 }
              end
            when 2
              size.times { |y| res[y * size, size].copy_from(buf[top, size]) }
            else
              size.times { |y| res[y * size, size].fill(buf[base - 1 + y * BPS]) }
            end
          end

          private def avg3(a : Int32, b : Int32, c : Int32) : UInt8
            ((a + 2 * b + c + 2) >> 2).to_u8
          end

          private def avg2(a : Int32, b : Int32) : UInt8
            ((a + b + 1) >> 1).to_u8
          end

          # 4x4 modes: 0 DC, 1 TM, 2 VE, 3 HE, 4 RD, 5 VR, 6 LD, 7 VL, 8 HD,
          # 9 HU. res[x + 4y].
          private def predict4(mode : Int32, buf : Bytes, base : Int32, res : Bytes) : Nil
            t = base - BPS
            tl = buf[t - 1].to_i32
            a, b, c, d = buf[t].to_i32, buf[t + 1].to_i32, buf[t + 2].to_i32, buf[t + 3].to_i32
            e, f, g, h = buf[t + 4].to_i32, buf[t + 5].to_i32, buf[t + 6].to_i32, buf[t + 7].to_i32
            i, j, k, l = buf[base - 1].to_i32, buf[base - 1 + BPS].to_i32, buf[base - 1 + 2 * BPS].to_i32, buf[base - 1 + 3 * BPS].to_i32
            case mode
            when 0
              res.fill(((a + b + c + d + i + j + k + l + 4) >> 3).to_u8)
            when 1
              4.times do |y|
                left = (y == 0 ? i : y == 1 ? j : y == 2 ? k : l) - tl
                4.times { |x| res[y * 4 + x] = (left + buf[t + x]).clamp(0, 255).to_u8 }
              end
            when 2
              vals = {avg3(tl, a, b), avg3(a, b, c), avg3(b, c, d), avg3(c, d, e)}
              4.times { |y| 4.times { |x| res[y * 4 + x] = vals[x] } }
            when 3
              rows = {avg3(tl, i, j), avg3(i, j, k), avg3(j, k, l), avg3(k, l, l)}
              4.times { |y| res[y * 4, 4].fill(rows[y]) }
            when 4
              set4(res, {0, 3}, avg3(j, k, l))
              set4(res, {1, 3, 0, 2}, avg3(i, j, k))
              set4(res, {2, 3, 1, 2, 0, 1}, avg3(tl, i, j))
              set4(res, {3, 3, 2, 2, 1, 1, 0, 0}, avg3(a, tl, i))
              set4(res, {3, 2, 2, 1, 1, 0}, avg3(b, a, tl))
              set4(res, {3, 1, 2, 0}, avg3(c, b, a))
              set4(res, {3, 0}, avg3(d, c, b))
            when 5
              set4(res, {0, 0, 1, 2}, avg2(tl, a))
              set4(res, {1, 0, 2, 2}, avg2(a, b))
              set4(res, {2, 0, 3, 2}, avg2(b, c))
              set4(res, {3, 0}, avg2(c, d))
              set4(res, {0, 3}, avg3(k, j, i))
              set4(res, {0, 2}, avg3(j, i, tl))
              set4(res, {0, 1, 1, 3}, avg3(i, tl, a))
              set4(res, {1, 1, 2, 3}, avg3(tl, a, b))
              set4(res, {2, 1, 3, 3}, avg3(a, b, c))
              set4(res, {3, 1}, avg3(b, c, d))
            when 6
              set4(res, {0, 0}, avg3(a, b, c))
              set4(res, {1, 0, 0, 1}, avg3(b, c, d))
              set4(res, {2, 0, 1, 1, 0, 2}, avg3(c, d, e))
              set4(res, {3, 0, 2, 1, 1, 2, 0, 3}, avg3(d, e, f))
              set4(res, {3, 1, 2, 2, 1, 3}, avg3(e, f, g))
              set4(res, {3, 2, 2, 3}, avg3(f, g, h))
              set4(res, {3, 3}, avg3(g, h, h))
            when 7
              set4(res, {0, 0}, avg2(a, b))
              set4(res, {1, 0, 0, 2}, avg2(b, c))
              set4(res, {2, 0, 1, 2}, avg2(c, d))
              set4(res, {3, 0, 2, 2}, avg2(d, e))
              set4(res, {0, 1}, avg3(a, b, c))
              set4(res, {1, 1, 0, 3}, avg3(b, c, d))
              set4(res, {2, 1, 1, 3}, avg3(c, d, e))
              set4(res, {3, 1, 2, 3}, avg3(d, e, f))
              set4(res, {3, 2}, avg3(e, f, g))
              set4(res, {3, 3}, avg3(f, g, h))
            when 8
              set4(res, {0, 0, 2, 1}, avg2(i, tl))
              set4(res, {0, 1, 2, 2}, avg2(j, i))
              set4(res, {0, 2, 2, 3}, avg2(k, j))
              set4(res, {0, 3}, avg2(l, k))
              set4(res, {3, 0}, avg3(a, b, c))
              set4(res, {2, 0}, avg3(tl, a, b))
              set4(res, {1, 0, 3, 1}, avg3(i, tl, a))
              set4(res, {1, 1, 3, 2}, avg3(j, i, tl))
              set4(res, {1, 2, 3, 3}, avg3(k, j, i))
              set4(res, {1, 3}, avg3(l, k, j))
            else
              set4(res, {0, 0}, avg2(i, j))
              set4(res, {2, 0, 0, 1}, avg2(j, k))
              set4(res, {2, 1, 0, 2}, avg2(k, l))
              set4(res, {1, 0}, avg3(i, j, k))
              set4(res, {3, 0, 1, 1}, avg3(j, k, l))
              set4(res, {3, 1, 1, 2}, avg3(k, l, l))
              set4(res, {3, 2, 2, 2, 0, 3, 1, 3, 2, 3, 3, 3}, l.to_u8)
            end
          end

          # Store `value` at each (x, y) pair listed in `coords`.
          private def set4(res : Bytes, coords : Tuple, value : UInt8) : Nil
            idx = 0
            while idx < coords.size
              res[coords[idx] + 4 * coords[idx + 1]] = value
              idx += 2
            end
          end

          # --- Transforms --------------------------------------------------

          # Forward 4x4 DCT of src - ref (libwebp FTransform), raster order.
          private def ftransform(src : Bytes, soff : Int32, sstride : Int32, ref : Bytes, roff : Int32, rstride : Int32, res : Slice(Int32), ooff : Int32) : Nil
            src_p = src.to_unsafe
            ref_p = ref.to_unsafe
            res_p = res.to_unsafe
            tmp_a = uninitialized StaticArray(Int32, 16)
            tmp = tmp_a.to_unsafe
            4.times do |i|
              s = soff + i * sstride
              r = roff + i * rstride
              d0 = src_p[s].to_i32 - ref_p[r]
              d1 = src_p[s + 1].to_i32 - ref_p[r + 1]
              d2 = src_p[s + 2].to_i32 - ref_p[r + 2]
              d3 = src_p[s + 3].to_i32 - ref_p[r + 3]
              a0 = d0 + d3
              a1 = d1 + d2
              a2 = d1 - d2
              a3 = d0 - d3
              tmp[i * 4] = (a0 + a1) * 8
              tmp[1 + i * 4] = (a2 * 2217 + a3 * 5352 + 1812) >> 9
              tmp[2 + i * 4] = (a0 - a1) * 8
              tmp[3 + i * 4] = (a3 * 2217 - a2 * 5352 + 937) >> 9
            end
            4.times do |i|
              a0 = tmp[i] + tmp[12 + i]
              a1 = tmp[4 + i] + tmp[8 + i]
              a2 = tmp[4 + i] - tmp[8 + i]
              a3 = tmp[i] - tmp[12 + i]
              res_p[ooff + i] = (a0 + a1 + 7) >> 4
              res_p[ooff + 4 + i] = ((a2 * 2217 + a3 * 5352 + 12000) >> 16) + (a3 != 0 ? 1 : 0)
              res_p[ooff + 8 + i] = (a0 - a1 + 7) >> 4
              res_p[ooff + 12 + i] = (a3 * 2217 - a2 * 5352 + 51000) >> 16
            end
          end

          # dst = clip(ref + inverse DCT), exactly the decoder's TransformOne.
          private def itransform(coeffs : Slice(Int32), coff : Int32, ref : Bytes, roff : Int32, rstride : Int32, dst : Bytes, doff : Int32, dstride : Int32) : Nil
            coeffs_p = coeffs.to_unsafe
            ref_p = ref.to_unsafe
            dst_p = dst.to_unsafe
            tmp_a = uninitialized StaticArray(Int32, 16)
            tmp = tmp_a.to_unsafe
            4.times do |i|
              x0 = coeffs_p[coff + i]
              x4 = coeffs_p[coff + 4 + i]
              x8 = coeffs_p[coff + 8 + i]
              x12 = coeffs_p[coff + 12 + i]
              a = x0 + x8
              b = x0 - x8
              c = mul2(x4) - mul1(x12)
              d = mul1(x4) + mul2(x12)
              tmp[i * 4] = a + d
              tmp[i * 4 + 1] = b + c
              tmp[i * 4 + 2] = b - c
              tmp[i * 4 + 3] = a - d
            end
            4.times do |i|
              dc = tmp[i] + 4
              a = dc + tmp[8 + i]
              b = dc - tmp[8 + i]
              c = mul2(tmp[4 + i]) - mul1(tmp[12 + i])
              d = mul1(tmp[4 + i]) + mul2(tmp[12 + i])
              r = roff + i * rstride
              o = doff + i * dstride
              dst_p[o] = (ref_p[r].to_i32 + ((a + d) >> 3)).clamp(0, 255).to_u8
              dst_p[o + 1] = (ref_p[r + 1].to_i32 + ((b + c) >> 3)).clamp(0, 255).to_u8
              dst_p[o + 2] = (ref_p[r + 2].to_i32 + ((b - c) >> 3)).clamp(0, 255).to_u8
              dst_p[o + 3] = (ref_p[r + 3].to_i32 + ((a - d) >> 3)).clamp(0, 255).to_u8
            end
          end

          private def mul1(a : Int32) : Int32
            ((a * 20091) >> 16) + a
          end

          private def mul2(a : Int32) : Int32
            (a * 35468) >> 16
          end

          # Walsh-Hadamard transform of the 16 luma DCs (block order) into
          # the Y2 block (libwebp FTransformWHT).
          private def fwht(dc : Slice(Int32), res : Slice(Int32)) : Nil
            tmp_a = uninitialized StaticArray(Int32, 16)
            tmp = tmp_a.to_unsafe
            4.times do |i|
              a0 = dc[i * 4] + dc[i * 4 + 2]
              a1 = dc[i * 4 + 1] + dc[i * 4 + 3]
              a2 = dc[i * 4 + 1] - dc[i * 4 + 3]
              a3 = dc[i * 4] - dc[i * 4 + 2]
              tmp[i * 4] = a0 + a1
              tmp[i * 4 + 1] = a3 + a2
              tmp[i * 4 + 2] = a3 - a2
              tmp[i * 4 + 3] = a0 - a1
            end
            4.times do |i|
              a0 = tmp[i] + tmp[8 + i]
              a1 = tmp[4 + i] + tmp[12 + i]
              a2 = tmp[4 + i] - tmp[12 + i]
              a3 = tmp[i] - tmp[8 + i]
              res[i] = (a0 + a1) >> 1
              res[4 + i] = (a3 + a2) >> 1
              res[8 + i] = (a3 - a2) >> 1
              res[12 + i] = (a0 - a1) >> 1
            end
          end

          # The decoder's inverse WHT: Y2 back to the 16 luma DCs.
          private def iwht(input : Slice(Int32), dc : Slice(Int32)) : Nil
            tmp_a = uninitialized StaticArray(Int32, 16)
            tmp = tmp_a.to_unsafe
            4.times do |i|
              a0 = input[i] + input[12 + i]
              a1 = input[4 + i] + input[8 + i]
              a2 = input[4 + i] - input[8 + i]
              a3 = input[i] - input[12 + i]
              tmp[i] = a0 + a1
              tmp[8 + i] = a0 - a1
              tmp[4 + i] = a3 + a2
              tmp[12 + i] = a3 - a2
            end
            4.times do |i|
              d = tmp[i * 4] + 3
              a0 = d + tmp[i * 4 + 3]
              a1 = tmp[i * 4 + 1] + tmp[i * 4 + 2]
              a2 = tmp[i * 4 + 1] - tmp[i * 4 + 2]
              a3 = d - tmp[i * 4 + 3]
              dc[i * 4] = (a0 + a1) >> 3
              dc[i * 4 + 1] = (a3 + a2) >> 3
              dc[i * 4 + 2] = (a0 - a1) >> 3
              dc[i * 4 + 3] = (a3 - a2) >> 3
            end
          end

          private def sse(a : Bytes, aoff : Int32, astride : Int32, b : Bytes, boff : Int32, bstride : Int32, size : Int32) : Int64
            a_p = a.to_unsafe
            b_p = b.to_unsafe
            sum = 0_i64
            size.times do |y|
              ar = aoff + y * astride
              br = boff + y * bstride
              size.times do |x|
                diff = a_p[ar + x].to_i32 - b_p[br + x]
                sum += diff * diff
              end
            end
            sum
          end

          # --- Token and mode syntax ---------------------------------------

          private def proba_base(type : Int32, n : Int32, ctx : Int32) : Int32
            ((type * 8 + @bands.unsafe_fetch(n)) * 3 + ctx) * 11
          end

          # Walk one block's tokens exactly as the decoder's GetCoeffs reads
          # them, yielding (bit, slot) per coded decision: slot >= 0 is an
          # adaptive coefficient probability, slot < 0 the fixed probability
          # -slot. Returns whether the block has a non-zero level from
          # `first` on (the context its neighbours see).
          private def each_token_bit(levels : Slice(Int16), off : Int32, first : Int32, type : Int32, ctx : Int32, &) : Bool
            lv = levels[off, 16].to_unsafe
            last = 15
            while last >= first && lv[last] == 0
              last -= 1
            end
            n = first
            base = proba_base(type, n, ctx)
            loop do
              if n > last
                yield false, base
                return last >= first
              end
              yield true, base
              while lv[n] == 0
                yield false, base + 1
                n += 1
                base = proba_base(type, n, 0)
              end
              yield true, base + 1
              level = lv[n].to_i32
              v = level.abs
              if v == 1
                yield false, base + 2
                next_ctx = 1
              else
                yield true, base + 2
                if v <= 4
                  yield false, base + 3
                  if v == 2
                    yield false, base + 4
                  else
                    yield true, base + 4
                    yield v == 4, base + 5
                  end
                elsif v <= 10
                  yield true, base + 3
                  yield false, base + 6
                  if v <= 6
                    yield false, base + 7
                    yield v == 6, -159
                  else
                    yield true, base + 7
                    yield v >= 9, -165
                    yield (v - 7).odd?, -145
                  end
                else
                  yield true, base + 3
                  yield true, base + 6
                  cat = v < 19 ? 0 : v < 35 ? 1 : v < 67 ? 2 : 3
                  yield cat >= 2, base + 8
                  yield cat.odd?, base + 9 + (cat >> 1)
                  rem = v - (3 + (8 << cat))
                  tab = CAT_PROBS[cat]
                  idx = 0
                  while idx < tab.size
                    yield (rem >> (tab.size - 1 - idx)) & 1 == 1, -tab[idx]
                    idx += 1
                  end
                end
                next_ctx = 2
              end
              yield level < 0, -128
              n += 1
              return true if n == 16
              base = proba_base(type, n, next_ctx)
            end
          end

          # Rate (1/256 bit) of one block under the default probabilities,
          # and its non-zero flag.
          private def block_cost(levels : Slice(Int16), off : Int32, first : Int32, type : Int32, ctx : Int32) : {Int64, Bool}
            cost = 0_i64
            nz = each_token_bit(levels, off, first, type, ctx) do |bit, slot|
              cost += if slot >= 0
                        bit ? @cost1.unsafe_fetch(slot) : @cost0.unsafe_fetch(slot)
                      else
                        bit ? COST[256 + slot] : COST[-slot]
                      end
            end
            {cost, nz}
          end

          private def bit_cost(bit : Bool, prob : Int32) : Int32
            bit ? COST[256 - prob] : COST[prob]
          end

          # Bits of the macroblock type (intra 16x16) and its mode.
          private def i16_mode_bits(mode : Int32, &) : Nil
            yield true, 145
            if mode == 1 || mode == 3
              yield true, 156
              yield mode == 1, 128
            else
              yield false, 156
              yield mode == 2, 163
            end
          end

          private def uv_mode_bits(mode : Int32, &) : Nil
            yield mode != 0, 142
            return if mode == 0
            yield mode != 2, 114
            return if mode == 2
            yield mode != 3, 183
          end

          # Sub-block mode tree (libwebp PutI4Mode) under `probs` (an offset
          # into BMODE_PROBS).
          def self.i4_mode_bits(mode : Int32, probs : Int32, &) : Nil
            yield mode != 0, BMODE_PROBS[probs].to_i32
            return if mode == 0
            yield mode != 1, BMODE_PROBS[probs + 1].to_i32
            return if mode == 1
            yield mode != 2, BMODE_PROBS[probs + 2].to_i32
            return if mode == 2
            if mode < 6
              yield false, BMODE_PROBS[probs + 3].to_i32
              yield mode != 3, BMODE_PROBS[probs + 4].to_i32
              return if mode == 3
              yield mode != 4, BMODE_PROBS[probs + 5].to_i32
            else
              yield true, BMODE_PROBS[probs + 3].to_i32
              yield mode != 6, BMODE_PROBS[probs + 6].to_i32
              return if mode == 6
              yield mode != 7, BMODE_PROBS[probs + 7].to_i32
              return if mode == 7
              yield mode != 8, BMODE_PROBS[probs + 8].to_i32
            end
          end

          # Rate of each sub-block mode in each (above, left) context, plus
          # the shared cost of nothing else: [(above * 10 + left) * 10 + mode].
          I4_MODE_COSTS = Slice(Int64).new(1000) do |idx|
            ctx = idx // 10
            cost = 0_i64
            i4_mode_bits(idx % 10, ctx * 9) { |bit, prob| cost += bit ? COST[256 - prob] : COST[prob] }
            cost
          end

          # --- Bitstream ---------------------------------------------------

          # Visit every coded block in bitstream order with the decoder's
          # contexts, yielding (levels offset, first, type, ctx); the block
          # returns its non-zero flag. With `use_skip`, skipped macroblocks
          # code nothing and only reset the contexts, as the decoder does.
          private def each_block(use_skip : Bool, &) : Nil
            top_nz = Slice(Int32).new(@mb_w, 0)
            top_dc = Slice(Int32).new(@mb_w, 0)
            @mb_h.times do |mby|
              left_nz = 0
              left_dc = 0
              @mb_w.times do |mbx|
                mb = mby * @mb_w + mbx
                lv = mb * LEVELS_PER_MB
                i4 = @is_i4[mb]
                if use_skip && @skip[mb]
                  top_nz[mbx] = left_nz = 0
                  top_dc[mbx] = left_dc = 0 unless i4
                  next
                end
                first, type = i4 ? {0, TYPE_I4} : {1, TYPE_I16_AC}
                unless i4
                  nz = yield lv, 0, TYPE_Y2, top_dc[mbx] + left_dc
                  top_dc[mbx] = left_dc = nz ? 1 : 0
                end
                tnz = top_nz[mbx]
                lnz = left_nz
                16.times do |n|
                  x = n & 3
                  y = n >> 2
                  nz = yield lv + (1 + n) * 16, first, type, ((tnz >> x) & 1) + ((lnz >> y) & 1)
                  tnz = nz ? tnz | (1 << x) : tnz & ~(1 << x)
                  lnz = nz ? lnz | (1 << y) : lnz & ~(1 << y)
                end
                8.times do |k|
                  ch = k >> 2
                  tbit = 1 << (4 + ch * 2 + (k & 1))
                  lbit = 1 << (4 + ch * 2 + ((k >> 1) & 1))
                  nz = yield lv + (17 + k) * 16, 0, TYPE_UV, (tnz & tbit != 0 ? 1 : 0) + (lnz & lbit != 0 ? 1 : 0)
                  tnz = nz ? tnz | tbit : tnz & ~tbit
                  lnz = nz ? lnz | lbit : lnz & ~lbit
                end
                top_nz[mbx] = tnz
                left_nz = lnz
              end
            end
          end

          private def write_frame : Bytes?
            mbs = @mb_w * @mb_h
            skipped = @skip.count(true)
            use_skip = skipped > 0
            skip_prob = ((mbs - skipped) * 255 // mbs).clamp(1, 254)
            probs = token_probs(use_skip)

            filter = (AC_TABLE[@q_index] >> 2) * 300 // 256
            filter = 0 if filter < 2

            bw = BoolWriter.new
            bw.put(false, 128) # colour space
            bw.put(false, 128) # clamping type
            bw.put(false, 128) # segmentation
            bw.put(false, 128) # normal loop filter
            bw.put_literal(filter.clamp(0, 63), 6)
            bw.put_literal(0, 3) # sharpness
            bw.put(false, 128)   # no loop-filter deltas
            bw.put_literal(0, 2) # one token partition
            bw.put_literal(@q_index, 7)
            bw.put_signed(0, 4) # y1 dc
            bw.put_signed(0, 4) # y2 dc
            bw.put_signed(0, 4) # y2 ac
            bw.put_signed(UV_DC_DELTA, 4)
            bw.put_signed(0, 4) # uv ac
            bw.put(false, 128)  # refresh entropy probs
            probs.size.times do |i|
              update = probs[i] != COEFF_PROBS[i]
              bw.put(update, COEFF_UPDATE_PROBS[i].to_i32)
              bw.put_literal(probs[i].to_i32, 8) if update
            end
            bw.put(use_skip, 128)
            bw.put_literal(skip_prob, 8) if use_skip

            top = Bytes.new(@mb_w * 4)
            @mb_h.times do |mby|
              left = Bytes.new(4)
              @mb_w.times do |mbx|
                mb = mby * @mb_w + mbx
                bw.put(@skip[mb], skip_prob) if use_skip
                if @is_i4[mb]
                  bw.put(false, 145)
                  16.times do |n|
                    x = n & 3
                    y = n >> 2
                    mode = @i4_modes[mb * 16 + n].to_i32
                    VP8.i4_mode_bits(mode, (top[mbx * 4 + x].to_i32 * 10 + left[y]) * 9) { |bit, prob| bw.put(bit, prob) }
                    top[mbx * 4 + x] = left[y] = mode.to_u8
                  end
                else
                  mode = @y_mode[mb].to_i32
                  i16_mode_bits(mode) { |bit, prob| bw.put(bit, prob) }
                  top[mbx * 4, 4].fill(mode.to_u8)
                  left.fill(mode.to_u8)
                end
                uv_mode_bits(@uv_mode[mb].to_i32) { |bit, prob| bw.put(bit, prob) }
              end
            end
            part0 = bw.finish
            return if part0.size > MAX_PARTITION0

            tokens = BoolWriter.new
            each_block(use_skip) do |off, first, type, ctx|
              each_token_bit(@levels, off, first, type, ctx) do |bit, slot|
                tokens.put(bit, slot >= 0 ? probs[slot].to_i32 : -slot)
              end
            end
            part1 = tokens.finish

            frame = Bytes.new(10 + part0.size + part1.size)
            tag = (1 << 4) | (part0.size << 5) # key frame, version 0, shown
            frame[0] = (tag & 0xFF).to_u8
            frame[1] = ((tag >> 8) & 0xFF).to_u8
            frame[2] = ((tag >> 16) & 0xFF).to_u8
            frame[3] = 0x9d_u8
            frame[4] = 0x01_u8
            frame[5] = 0x2a_u8
            frame[6] = (@width & 0xFF).to_u8
            frame[7] = (@width >> 8).to_u8
            frame[8] = (@height & 0xFF).to_u8
            frame[9] = (@height >> 8).to_u8
            frame[10, part0.size].copy_from(part0)
            frame[10 + part0.size, part1.size].copy_from(part1)
            frame
          end

          # The token probabilities this frame codes with: each default the
          # frame's own statistics beat by more than the update costs is
          # replaced (libwebp FinalizeTokenProbas).
          private def token_probs(use_skip : Bool) : Bytes
            zeros = Slice(Int64).new(COEFF_PROBS.size, 0_i64)
            ones = Slice(Int64).new(COEFF_PROBS.size, 0_i64)
            each_block(use_skip) do |off, first, type, ctx|
              each_token_bit(@levels, off, first, type, ctx) do |bit, slot|
                next unless slot >= 0
                bit ? (ones[slot] += 1) : (zeros[slot] += 1)
              end
            end
            probs = COEFF_PROBS.dup
            probs.size.times do |i|
              total = zeros[i] + ones[i]
              next if total == 0
              old = COEFF_PROBS[i].to_i32
              upd = COEFF_UPDATE_PROBS[i].to_i32
              fresh = (255 - ones[i] * 255 // total).clamp(1, 255).to_i32
              old_cost = zeros[i] * COST[old] + ones[i] * COST[256 - old] + COST[upd]
              new_cost = zeros[i] * COST[fresh] + ones[i] * COST[256 - fresh] + COST[256 - upd] + 8 * 256
              probs[i] = fresh.to_u8 if new_cost < old_cost
            end
            probs
          end
        end
      end
    end
  end
end
