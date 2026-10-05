require "../../../spec_helper"

private TRANSLATIONS_CONFIG = <<-TOML
  title = "My Site"
  base_url = "https://example.com"
  default_language = "en"

  [languages.en]
  language_name = "English"
  weight = 1

  [languages.ko]
  language_name = "Korean"
  weight = 2

  [languages.ja]
  language_name = "Japanese"
  weight = 3
  TOML

private def translation_issues(files : Hash(String, String), config : String = TRANSLATIONS_CONFIG) : Array(Hwaro::Services::Issue)
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, "config.toml"), config)
    files.each do |path, body|
      full = File.join(dir, "content", path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, body)
    end
    doctor = Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: File.join(dir, "config.toml"))
    doctor.run.select(&.category.==("i18n"))
  end
end

private def summarize(issues : Array(Hwaro::Services::Issue)) : Array(String)
  issues.map { |i| "#{i.language} #{i.id} #{i.file.not_nil!.split("/content/").last}" }
end

private PAGE = "+++\ntitle = \"T\"\n+++\nbody\n"

describe "Hwaro::Services::Doctor translations" do
  it "reports missing translations and orphans per language, as info" do
    issues = translation_issues({
      "_index.md"             => PAGE,
      "_index.ko.md"          => PAGE,
      "_index.ja.md"          => PAGE,
      "a.md"                  => PAGE,
      "a.ko.md"               => PAGE,
      "b.en.md"               => PAGE, # explicit default suffix pairs like the build
      "b.ko.md"               => PAGE,
      "b.ja.md"               => PAGE,
      "only.ja.md"            => PAGE,
      "blog/_index.md"        => PAGE,
      "blog/_index.ja.md"     => PAGE,
      "blog/post/index.md"    => PAGE,
      "blog/post/index.ko.md" => PAGE,
      "blog/post/index.ja.md" => PAGE,
    })

    summarize(issues).should eq([
      "ko translation-missing blog/_index.md",
      "ja translation-missing a.md",
      "ja translation-orphan only.ja.md",
    ])
    issues.all?(&.level.==(:info)).should be_true
    issues.first.message.should eq("No 'ko' translation")
    issues.last.message.should eq("'ja' translation has no 'en' original")
  end

  it "ignores drafts and future pages on both sides" do
    issues = translation_issues({
      "a.md"    => "+++\ntitle = \"A\"\ndraft = true\n+++\nbody\n",
      "a.ko.md" => PAGE,
      "a.ja.md" => PAGE,
      "b.md"    => PAGE,
      "b.ko.md" => "+++\ntitle = \"B\"\ndate = 2999-01-01\n+++\nbody\n",
      "b.ja.md" => PAGE,
    })
    summarize(issues).should eq([
      "ko translation-orphan a.ko.md",
      "ko translation-missing b.md",
      "ja translation-orphan a.ja.md",
    ])
  end

  it "reports nothing on a single-language site" do
    translation_issues({"a.md" => PAGE, "a.ko.md" => PAGE}, %(title = "T"\nbase_url = "https://example.com"\n)).should be_empty
  end

  it "respects [doctor] ignore" do
    config = TRANSLATIONS_CONFIG + %(\n[doctor]\nignore = ["translation-missing"]\n)
    summarize(translation_issues({"a.md" => PAGE, "only.ko.md" => PAGE}, config)).should eq(["ko translation-orphan only.ko.md"])
  end

  it "carries the language in JSON only on translation issues" do
    issue = Hwaro::Services::Issue.new(id: "translation-missing", level: :info, category: "i18n", file: "content/a.md", message: "No 'ko' translation", language: "ko")
    JSON.parse(issue.to_json)["language"].should eq("ko")
    other = Hwaro::Services::Issue.new(id: "title-default", level: :warning, category: "config", file: nil, message: "m")
    JSON.parse(other.to_json).as_h.has_key?("language").should be_false
  end
end
