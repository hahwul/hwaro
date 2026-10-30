require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module DateFilters
          # Month, weekday and AM/PM names for one locale: CLDR "format"
          # context, wide and abbreviated. Weekdays run Monday first, matching
          # `Time::DayOfWeek#value` (Monday = 1 … Sunday = 7).
          # `%p` and `%P` both print `am`/`pm` as written: only English has a
          # lowercase variant (Crystal's `am`/`pm`), and lowercasing a CLDR
          # form makes a non-word in vi (`ch`) or tr (`ös`). `upcase` is the
          # case rule `%^` applies (Turkish needs `i` → `İ`).
          record LocaleNames,
            months : Array(String),
            months_abbr : Array(String),
            days : Array(String),
            days_abbr : Array(String),
            am : String,
            pm : String,
            upcase : Unicode::CaseOptions = Unicode::CaseOptions::None

          # `Time#to_s(format)` raises a bare Crystal `IndexError` on a
          # malformed format string (a trailing `%`, e.g. `date("%")`) — not a
          # `Crinja::Error`, so it escapes the render phase's rescue and
          # aborts the whole build with `Index out of bounds` and no template
          # file:line. Re-raise as a Crinja error so the failure names the bad
          # format AND points at the template line that wrote it.
          #
          # `locale` (`ko`, `ko_KR`, `ko-KR`, …) localizes the name directives
          # `%a %A %b %h %B %p %P` (and their `%^` upcase forms). Empty, or any
          # English locale, is Crystal's own output byte for byte.
          def self.format_time(time : Time, format : String, locale : String = "") : String
            names = locale.empty? ? nil : locale_names(locale)
            marked = names ? mark_names(format) : nil
            return time.to_s(format) unless names && marked
            fill_names(time.to_s(marked), time, names)
          rescue ex : IndexError | ArgumentError
            raise Crinja::TypeError.new("invalid date format #{format.inspect}: #{ex.message}")
          end

          # The `locale=` argument as a string; none/undefined (an unset
          # `page.language`) or a non-string means "no locale".
          def self.locale_arg(value : Crinja::Value) : String
            case raw = value.raw
            when String, Crinja::SafeString then raw.to_s
            else                                 ""
            end
          end

          # The name table for `locale`, or nil for Crystal's English names.
          # Case-insensitive, `-` or `_` separated, ignores a POSIX
          # `.codeset` / `@modifier` (`ko_KR.UTF-8`, `ko@euro`), and falls
          # back one subtag at a time (`zh-Hant-TW` → `zh_hant` → `zh`). An
          # unknown locale warns once per build and renders English.
          def self.locale_names(locale : String) : LocaleNames?
            # Fast path: the canonical keys `page.language` usually holds.
            LOCALES[locale]?.try { |names| return names }
            return if locale == "en"
            key = locale.strip.downcase.tr("-", "_")
            return if key.empty? # `locale=" "` is no locale, not an unknown one
            key = key[0, key.index(/[.@]/) || key.size]
            loop do
              return if key == "en"
              LOCALES[key]?.try { |names| return names }
              cut = key.rindex('_') || break
              key = key[0, cut]
            end
            warn_unknown_locale(locale)
            nil
          end

          @@warned_locales = Set(String).new
          @@warned_mutex = Mutex.new

          private def self.warn_unknown_locale(locale : String) : Nil
            first = @@warned_mutex.synchronize { @@warned_locales.add?(locale) }
            Logger.warn "date: unknown locale #{locale.inspect}; month and weekday names render in English." if first
          end

          # Called at the start of every build (Builder#run) and serve pass
          # (Builder#begin_serve_pass), so a locale that is still wrong warns
          # again on the next rebuild.
          def self.clear_locale_warnings : Nil
            @@warned_mutex.synchronize { @@warned_locales.clear }
          end

          # Name directives become one marker char each (a Unicode
          # noncharacter, U+FDD0 + kind), `Time#to_s` formats the rest, and
          # `fill_names` swaps the markers for names afterwards. Splicing the
          # names into the format instead let a dangling prefix (`%-`, `%_`,
          # `%^`, `%:`, `%3`) re-read a name's first letter as a directive:
          # `%_%a` in French printed " 3ar." for "%_mar.". A marker is never a
          # directive, so it prints literally wherever it lands.
          #
          # A `%` pair that is not a name directive (`%%`, `%-d`, `%_m`, `%3N`,
          # …) is copied verbatim, which tokenizes the way `Time::Format` does.
          # Returns nil when there is nothing to localize, or when the format
          # itself holds a marker char (never in real text), to stay English.
          def self.mark_names(format : String) : String?
            found = false
            marked = String.build(format.bytesize + 4) do |io|
              reader = Char::Reader.new(format)
              while reader.has_next?
                char = reader.current_char
                return if MARKER_RANGE.includes?(char.ord)
                reader.next_char
                unless char == '%' && reader.has_next?
                  io << char # a trailing `%` stays and raises in `Time#to_s`
                  next
                end
                directive = reader.current_char
                upcase = directive == '^' && reader.peek_next_char.in?('a', 'A', 'b', 'h', 'B')
                directive = reader.next_char if upcase
                reader.next_char
                if kind = NAME_KINDS.index(directive == 'h' ? 'b' : directive)
                  found = true
                  io << (MARKER_BASE + kind + (upcase ? UPCASE_OFFSET : 0)).chr
                else
                  io << '%' << directive
                end
              end
            end
            marked if found
          end

          NAME_KINDS    = {'a', 'A', 'b', 'B', 'p', 'P'}
          MARKER_BASE   = 0xFDD0
          UPCASE_OFFSET = NAME_KINDS.size
          MARKER_RANGE  = MARKER_BASE...(MARKER_BASE + 2 * NAME_KINDS.size)

          private def self.fill_names(text : String, time : Time, names : LocaleNames) : String
            String.build(text.bytesize + 32) do |io|
              text.each_char do |char|
                ord = char.ord
                unless MARKER_RANGE.includes?(ord)
                  io << char
                  next
                end
                kind = (ord - MARKER_BASE) % UPCASE_OFFSET
                name = case NAME_KINDS[kind]
                       when 'a' then names.days_abbr[time.day_of_week.value - 1]
                       when 'A' then names.days[time.day_of_week.value - 1]
                       when 'b' then names.months_abbr[time.month - 1]
                       when 'B' then names.months[time.month - 1]
                       else          time.hour < 12 ? names.am : names.pm
                       end
                io << (ord - MARKER_BASE >= UPCASE_OFFSET ? name.upcase(names.upcase) : name)
              end
            end
          end

          # Zoned forms come first: `Time.parse` ignores trailing input, so a
          # zone-less format would accept "10:30:00-03:30" and drop the offset.
          # The space-separated forms include `Time#to_s` output
          # ("2024-03-05 08:00:00 UTC"), which is how front matter and data
          # file datetimes reach templates.
          T_ZONED     = {"%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S.%N%z", "%Y-%m-%dT%H:%M%z"}
          T_LOCAL     = {"%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"}
          SPACE_ZONED = {"%Y-%m-%d %H:%M:%S %z", "%Y-%m-%d %H:%M:%S%z", "%Y-%m-%d %H:%M:%S.%N %z", "%Y-%m-%d %H:%M %z", "%Y-%m-%d %H:%M%z"}
          SPACE_LOCAL = {"%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"}

          # No date-only fallback for longer strings: `%Y-%m-%d` consumes only
          # the first 10 chars, which would silently reformat garbage like
          # "2024-01-15xxx" instead of passing it through unchanged.
          def self.parse_string(value : String) : Time?
            return try_parse(value, "%Y-%m-%d") if value.size <= 10
            if value[10].in?('T', 't')
              value = value.upcase # RFC 3339 allows a lowercase `t` and `z`
              zoned, local = T_ZONED, T_LOCAL
            else
              zoned, local = SPACE_ZONED, SPACE_LOCAL
            end
            # Longer than the zone-less minute form ("2024-01-15T10:30").
            if value.size > 16
              zoned.each { |fmt| try_parse(value, fmt).try { |time| return time } }
            end
            local.each { |fmt| try_parse(value, fmt).try { |time| return time } }
            nil
          end

          private def self.try_parse(value : String, format : String) : Time?
            Time.parse(value, format, Time::Location::UTC)
          rescue Time::Format::Error | Time::Error | ArgumentError
            nil
          end

          def self.register(env : Crinja)
            # Date formatting filter
            env.filters["date"] = Crinja.filter({format: "%Y-%m-%d", locale: nil}) do
              value = target.raw
              format = arguments["format"].to_s
              locale = DateFilters.locale_arg(arguments["locale"])

              case value
              when Time
                DateFilters.format_time(value, format, locale)
              when String, Crinja::SafeString
                parsed = DateFilters.parse_string(value.to_s)
                parsed ? DateFilters.format_time(parsed, format, locale) : value.to_s
              else
                value.to_s
              end
            end
          end

          # Built-in name tables, CLDR "format" context (the form used inside a
          # date, so Russian and Polish months are genitive: "5 марта",
          # "5 marca"). `pt` is Brazilian Portuguese, as in CLDR, so `pt_BR`
          # resolves to it; Traditional Chinese (`zh_TW`) also serves `zh_Hant`,
          # `zh_HK` and `zh_MO`. English is Crystal's own names, not a table.
          # AM/PM is the abbreviated CLDR form, except Korean, which uses the
          # wide 오전/오후 on purpose (ICU's Korean patterns print it too).
          ZH_HANT = LocaleNames.new(
            months: %w[1月 2月 3月 4月 5月 6月 7月 8月 9月 10月 11月 12月],
            months_abbr: %w[1月 2月 3月 4月 5月 6月 7月 8月 9月 10月 11月 12月],
            days: %w[星期一 星期二 星期三 星期四 星期五 星期六 星期日],
            days_abbr: %w[週一 週二 週三 週四 週五 週六 週日],
            am: "上午", pm: "下午")

          LOCALES = {
            "ko" => LocaleNames.new(
              months: %w[1월 2월 3월 4월 5월 6월 7월 8월 9월 10월 11월 12월],
              months_abbr: %w[1월 2월 3월 4월 5월 6월 7월 8월 9월 10월 11월 12월],
              days: %w[월요일 화요일 수요일 목요일 금요일 토요일 일요일],
              days_abbr: %w[월 화 수 목 금 토 일],
              am: "오전", pm: "오후"),
            "ja" => LocaleNames.new(
              months: %w[1月 2月 3月 4月 5月 6月 7月 8月 9月 10月 11月 12月],
              months_abbr: %w[1月 2月 3月 4月 5月 6月 7月 8月 9月 10月 11月 12月],
              days: %w[月曜日 火曜日 水曜日 木曜日 金曜日 土曜日 日曜日],
              days_abbr: %w[月 火 水 木 金 土 日],
              am: "午前", pm: "午後"),
            "zh" => LocaleNames.new(
              months: %w[一月 二月 三月 四月 五月 六月 七月 八月 九月 十月 十一月 十二月],
              months_abbr: %w[1月 2月 3月 4月 5月 6月 7月 8月 9月 10月 11月 12月],
              days: %w[星期一 星期二 星期三 星期四 星期五 星期六 星期日],
              days_abbr: %w[周一 周二 周三 周四 周五 周六 周日],
              am: "上午", pm: "下午"),
            "zh_tw"   => ZH_HANT,
            "zh_hant" => ZH_HANT,
            "zh_hk"   => ZH_HANT,
            "zh_mo"   => ZH_HANT,
            "de"      => LocaleNames.new(
              months: %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember],
              months_abbr: %w[Jan. Feb. März Apr. Mai Juni Juli Aug. Sept. Okt. Nov. Dez.],
              days: %w[Montag Dienstag Mittwoch Donnerstag Freitag Samstag Sonntag],
              days_abbr: %w[Mo. Di. Mi. Do. Fr. Sa. So.],
              am: "AM", pm: "PM"),
            "fr" => LocaleNames.new(
              months: %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre],
              months_abbr: %w[janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.],
              days: %w[lundi mardi mercredi jeudi vendredi samedi dimanche],
              days_abbr: %w[lun. mar. mer. jeu. ven. sam. dim.],
              am: "AM", pm: "PM"),
            "es" => LocaleNames.new(
              months: %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre],
              months_abbr: %w[ene feb mar abr may jun jul ago sept oct nov dic],
              days: %w[lunes martes miércoles jueves viernes sábado domingo],
              days_abbr: %w[lun mar mié jue vie sáb dom],
              am: "a. m.", pm: "p. m."),
            "it" => LocaleNames.new(
              months: %w[gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre],
              months_abbr: %w[gen feb mar apr mag giu lug ago set ott nov dic],
              days: %w[lunedì martedì mercoledì giovedì venerdì sabato domenica],
              days_abbr: %w[lun mar mer gio ven sab dom],
              am: "AM", pm: "PM"),
            "pt" => LocaleNames.new(
              months: %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro],
              months_abbr: %w[jan. fev. mar. abr. mai. jun. jul. ago. set. out. nov. dez.],
              days: %w[segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado domingo],
              days_abbr: %w[seg. ter. qua. qui. sex. sáb. dom.],
              am: "AM", pm: "PM"),
            "ru" => LocaleNames.new(
              months: %w[января февраля марта апреля мая июня июля августа сентября октября ноября декабря],
              months_abbr: %w[янв. февр. мар. апр. мая июн. июл. авг. сент. окт. нояб. дек.],
              days: %w[понедельник вторник среда четверг пятница суббота воскресенье],
              days_abbr: %w[пн вт ср чт пт сб вс],
              am: "AM", pm: "PM"),
            "nl" => LocaleNames.new(
              months: %w[januari februari maart april mei juni juli augustus september oktober november december],
              months_abbr: %w[jan feb mrt apr mei jun jul aug sep okt nov dec],
              days: %w[maandag dinsdag woensdag donderdag vrijdag zaterdag zondag],
              days_abbr: %w[ma di wo do vr za zo],
              am: "a.m.", pm: "p.m."),
            "pl" => LocaleNames.new(
              months: %w[stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia],
              months_abbr: %w[sty lut mar kwi maj cze lip sie wrz paź lis gru],
              days: %w[poniedziałek wtorek środa czwartek piątek sobota niedziela],
              days_abbr: %w[pon. wt. śr. czw. pt. sob. niedz.],
              am: "AM", pm: "PM"),
            "tr" => LocaleNames.new(
              months: %w[Ocak Şubat Mart Nisan Mayıs Haziran Temmuz Ağustos Eylül Ekim Kasım Aralık],
              months_abbr: %w[Oca Şub Mar Nis May Haz Tem Ağu Eyl Eki Kas Ara],
              days: %w[Pazartesi Salı Çarşamba Perşembe Cuma Cumartesi Pazar],
              days_abbr: %w[Pzt Sal Çar Per Cum Cmt Paz],
              am: "ÖÖ", pm: "ÖS", upcase: Unicode::CaseOptions::Turkic),
            "vi" => LocaleNames.new(
              months: ["tháng 1", "tháng 2", "tháng 3", "tháng 4", "tháng 5", "tháng 6",
                       "tháng 7", "tháng 8", "tháng 9", "tháng 10", "tháng 11", "tháng 12"],
              months_abbr: ["thg 1", "thg 2", "thg 3", "thg 4", "thg 5", "thg 6",
                            "thg 7", "thg 8", "thg 9", "thg 10", "thg 11", "thg 12"],
              days: ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật"],
              days_abbr: ["Th 2", "Th 3", "Th 4", "Th 5", "Th 6", "Th 7", "CN"],
              am: "SA", pm: "CH"),
            "id" => LocaleNames.new(
              months: %w[Januari Februari Maret April Mei Juni Juli Agustus September Oktober November Desember],
              months_abbr: %w[Jan Feb Mar Apr Mei Jun Jul Agu Sep Okt Nov Des],
              days: %w[Senin Selasa Rabu Kamis Jumat Sabtu Minggu],
              days_abbr: %w[Sen Sel Rab Kam Jum Sab Min],
              am: "AM", pm: "PM"),
          }
        end
      end
    end
  end
end
