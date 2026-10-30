require "../../../../spec_helper"
require "../../../../../src/content/processors/template"

private alias DateFilters = Hwaro::Content::Processors::Filters::DateFilters

# Tuesday 5 March 2024, 14:07:09 (afternoon) and a Sunday-in-December morning.
private TUE_PM = Time.utc(2024, 3, 5, 14, 7, 9)
private SUN_AM = Time.utc(2023, 12, 31, 9, 0, 0)

private def localized(format : String, locale : String, time : Time = TUE_PM) : String
  render_crinja("{{ d | date(format=f, locale=l) }}", {
    "d" => Crinja::Value.new(time), "f" => Crinja::Value.new(format), "l" => Crinja::Value.new(locale),
  })
end

describe "DateFilters locale" do
  before_each { DateFilters.clear_locale_warnings }

  it "renders the issue's Korean example" do
    localized("%B %-d일 (%a)", "ko").should eq("3월 5일 (화)")
  end

  # {locale, %B, %b, %A, %a, %P} for TUE_PM.
  {
    {"ko", "3월", "3월", "화요일", "화", "오후"},
    {"ja", "3月", "3月", "火曜日", "火", "午後"},
    {"zh", "三月", "3月", "星期二", "周二", "下午"},
    {"zh_TW", "3月", "3月", "星期二", "週二", "下午"},
    {"de", "März", "März", "Dienstag", "Di.", "PM"},
    {"fr", "mars", "mars", "mardi", "mar.", "PM"},
    {"es", "marzo", "mar", "martes", "mar", "p. m."},
    {"it", "marzo", "mar", "martedì", "mar", "PM"},
    {"pt", "março", "mar.", "terça-feira", "ter.", "PM"},
    {"ru", "марта", "мар.", "вторник", "вт", "PM"},
    {"nl", "maart", "mrt", "dinsdag", "di", "p.m."},
    {"pl", "marca", "mar", "wtorek", "wt.", "PM"},
    {"tr", "Mart", "Mar", "Salı", "Sal", "ÖS"},
    {"vi", "tháng 3", "thg 3", "Thứ Ba", "Th 3", "CH"},
    {"id", "Maret", "Mar", "Selasa", "Sel", "PM"},
  }.each do |locale, month, month_abbr, day, day_abbr, pm|
    it "localizes every name directive for #{locale}" do
      localized("%B|%b|%h|%A|%a|%P|%p", locale).should eq(
        [month, month_abbr, month_abbr, day, day_abbr, pm, pm].join('|'))
    end
  end

  it "prints the CLDR AM/PM form for %p as well as %P (vi, tr have no lowercase form)" do
    localized("%p %P", "vi").should eq("CH CH")
    localized("%p %P", "tr", SUN_AM).should eq("ÖÖ ÖÖ")
  end

  it "never lets an incomplete prefix before a name read the name as a directive" do
    {"%-", "%_", "%^", "%:", "%::", "%3", "%6", "%9"}.each do |prefix|
      %w[a A b h B p P].each do |directive|
        format = "#{prefix}%#{directive}"
        # English: the prefix prints literally, then the name.
        TUE_PM.to_s(format).should eq(prefix + TUE_PM.to_s("%#{directive}"))
        {"fr", "nl", "de", "ko"}.each do |locale|
          {TUE_PM, SUN_AM, Time.utc(2024, 5, 5), Time.utc(2024, 4, 1)}.each do |time|
            localized(format, locale, time).should eq(prefix + localized("%#{directive}", locale, time))
          end
        end
      end
    end
    localized("%_%a", "fr").should eq("%_mar.")
    localized("%-%a", "fr", SUN_AM).should eq("%-dim.")
    localized("%-%b", "nl", Time.utc(2024, 5, 5)).should eq("%-mei")
    localized("%^%B", "de", Time.utc(2024, 4, 1)).should eq("%^April")
  end

  it "uses the Sunday/December/morning ends of each table" do
    localized("%A %a %B %b %P", "ko", SUN_AM).should eq("일요일 일 12월 12월 오전")
    localized("%A %a %B %b %P", "ja", SUN_AM).should eq("日曜日 日 12月 12月 午前")
    localized("%A %B", "zh", SUN_AM).should eq("星期日 十二月")
    localized("%-d %B", "ru", SUN_AM).should eq("31 декабря")
    localized("%a %b", "de", SUN_AM).should eq("So. Dez.")
  end

  it "upcases the %^ forms in the locale" do
    localized("%^B %^b %^A %^a", "de").should eq("MÄRZ MÄRZ DIENSTAG DI.")
    localized("%^B", "ko").should eq("3월")
  end

  it "upcases Turkish with the dotted capital İ" do
    localized("%^B", "tr", Time.utc(2024, 4, 1)).should eq("NİSAN")
    localized("%^B %^a", "tr", Time.utc(2024, 10, 1)).should eq("EKİM SAL")
    localized("%^A", "tr-TR", Time.utc(2024, 10, 2)).should eq("ÇARŞAMBA")
  end

  it "leaves every other directive to Time::Format" do
    format = "%Y-%m-%d %-d %e %_m %-m %H:%M:%S %I %j %3N %z %:z %% %%B %-B %_B %^Z %u %w"
    localized(format, "ko").should eq(TUE_PM.to_s(format))
  end

  it "renders the composite %c and %r directives in English, as before" do
    localized("%c|%r", "ko").should eq(TUE_PM.to_s("%c|%r"))
  end

  it "accepts ko, ko_KR, ko-KR and any case" do
    %w[ko ko_KR ko-KR KO-kr Ko_Kr].each { |loc| localized("%A", loc).should eq("화요일") }
  end

  it "falls back from region to language, one subtag at a time" do
    localized("%B", "pt_BR").should eq("março")
    localized("%B", "fr-CA").should eq("mars")
    localized("%a", "zh-Hant-TW").should eq("週二")
    localized("%a", "zh_HK").should eq("週二")
    localized("%a", "zh-Hans-CN").should eq("周二")
  end

  it "ignores a POSIX codeset or modifier" do
    log = with_captured_log do
      %w[ko.UTF-8 ko@euro ko_KR.UTF-8 ko_KR.UTF-8@x].each { |loc| localized("%A", loc).should eq("화요일") }
    end
    log.should_not contain("unknown locale")
  end

  it "keeps Crystal's English output for English locales, with no warning" do
    log = with_captured_log do
      %w[en en_US en-GB].each { |loc| localized("%B %a %p", loc).should eq(TUE_PM.to_s("%B %a %p")) }
    end
    log.should_not contain("unknown locale")
  end

  it "is unchanged without a locale, with an empty one, or with none" do
    expected = TUE_PM.to_s("%B %A %p")
    vars = {"d" => Crinja::Value.new(TUE_PM)}
    render_crinja("{{ d | date(format='%B %A %p') }}", vars).should eq(expected)
    render_crinja("{{ d | date(format='%B %A %p', locale='') }}", vars).should eq(expected)
    render_crinja("{{ d | date(format='%B %A %p', locale=none) }}", vars).should eq(expected)
    render_crinja("{{ d | date(format='%B %A %p', locale=missing) }}", vars).should eq(expected)
  end

  it "works with locale=page.language in a shared template" do
    tpl = "{{ page.date | date(format='%B', locale=page.language) }}"
    {"ko" => "3월", "fr" => "mars", "en" => "March"}.each do |lang, expected|
      page = Crinja::Value.new({"date" => Crinja::Value.new(TUE_PM), "language" => Crinja::Value.new(lang)})
      render_crinja(tpl, {"page" => page}).should eq(expected)
    end
  end

  it "accepts a positional locale" do
    render_crinja("{{ d | date('%a', 'ja') }}", {"d" => Crinja::Value.new(TUE_PM)}).should eq("火")
  end

  it "localizes string inputs as well as Time values" do
    render_crinja("{{ d | date(format='%B %-d', locale='ko') }}", {"d" => Crinja::Value.new("2024-03-05")}).should eq("3월 5")
    render_crinja("{{ d | date(format='%A', locale='ko') }}", {"d" => Crinja::Value.new("2024-03-05T14:07:09+09:00")}).should eq("화요일")
    render_crinja("{{ d | date(format='%B', locale='ko') }}", {"d" => Crinja::Value.new("not a date")}).should eq("not a date")
  end

  it "warns once per unknown locale and falls back to English" do
    log = with_captured_log do
      3.times { localized("%B %a", "xx").should eq("March Tue") }
      localized("%B", "yy-ZZ").should eq("March")
    end
    log.scan(/unknown locale "xx"/).size.should eq(1)
    log.scan(/unknown locale "yy-ZZ"/).size.should eq(1)
  end

  it "warns once per locale across parallel worker threads" do
    locales = (0...300).map { |i| "q#{i}" }
    sink = IO::Memory.new
    with_captured_log do
      # A bare IO::Memory drops lines under concurrent writers; production
      # stderr goes through GuardedIO, so the capture does too.
      Hwaro::Logger.io = Hwaro::Logger::GuardedIO.new(sink)
      context = Fiber::ExecutionContext::Parallel.new("date-locale-spec", 8)
      done = Channel(Nil).new
      8.times do |t|
        context.spawn do
          # Each worker walks the list from a different offset so threads
          # collide on the same fresh locale.
          locales.size.times { |i| DateFilters.format_time(TUE_PM, "%B", locales[(i + t) % locales.size]) }
          done.send(nil)
        end
      end
      context.wake_idle_schedulers(8)
      # Unguarded, concurrent `Set#add?` corrupts the hash and a worker spins
      # forever (seen when the Mutex was removed); fail instead of hanging.
      8.times do
        select
        when done.receive
        when timeout(30.seconds)
          fail "date-locale workers hung: the warn-once set was corrupted by concurrent access"
        end
      end
    end
    log = sink.to_s
    locales.each { |loc| log.scan(/unknown locale "#{loc}"/).size.should eq(1) }
  end

  it "treats a whitespace-only locale as no locale, without a warning" do
    log = with_captured_log { localized("%B", "  ").should eq("March") }
    log.should_not contain("unknown locale")
  end

  it "accepts a safe-string locale" do
    vars = {"d" => Crinja::Value.new(TUE_PM)}
    render_crinja("{{ d | date(format='%A', locale=('ko' | safe)) }}", vars).should eq("화요일")
    render_crinja("{{ now(format='%P', locale=('ja' | safe)) }}").should match(/\A午[前後]\z/)
  end

  it "warns again after the per-build reset" do
    first = with_captured_log { localized("%B", "xx") }
    DateFilters.clear_locale_warnings
    second = with_captured_log { localized("%B", "xx") }
    first.should contain(%(unknown locale "xx"))
    second.should contain(%(unknown locale "xx"))
  end

  it "still reports a malformed format by its original text" do
    expect_raises(Crinja::Error, %(invalid date format "%B %")) { localized("%B %", "ko") }
  end

  it "formats a safe string and a lowercase RFC 3339 t/z" do
    render_crinja(%({{ ("2024-03-05" | safe) | date("%B %d, %Y") }})).should eq("March 05, 2024")
    render_crinja(%({{ "2024-03-05t14:07:09z" | date("%B %d %H:%M %z") }})).should eq("March 05 14:07 +0000")
    render_crinja(%({{ "2024-03-05t14:07" | date("%H:%M") }})).should eq("14:07")
  end

  it "passes the locale through now(format=...)" do
    now_day = render_crinja("{{ now(format='%a', locale='ko') }}")
    %w[월 화 수 목 금 토 일].should contain(now_day)
  end
end
