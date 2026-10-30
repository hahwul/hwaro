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
        [month, month_abbr, month_abbr, day, day_abbr, pm, pm.downcase].join('|'))
    end
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

  it "warns once across parallel render fibers" do
    log = with_captured_log do
      done = Channel(Nil).new
      8.times do
        spawn do
          10.times { localized("%B", "qq") }
          done.send(nil)
        end
      end
      8.times { done.receive }
    end
    log.scan(/unknown locale "qq"/).size.should eq(1)
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

  it "passes the locale through now(format=...)" do
    now_day = render_crinja("{{ now(format='%a', locale='ko') }}")
    %w[월 화 수 목 금 토 일].should contain(now_day)
  end
end
