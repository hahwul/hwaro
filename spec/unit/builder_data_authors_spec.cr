require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose site for testing
module Hwaro::Core::Build
  class Builder
    def site
      @site
    end
  end
end

module Hwaro::Core::Build
  describe Builder do
    it "loads data and aggregates authors" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          # Create data directory
          FileUtils.mkdir_p("data")
          File.write("data/authors.yml", <<-YAML
            john-doe:
              name: "John Doe"
              twitter: "@johndoe"
              bio: "A software engineer."
            jane-smith:
              name: "Jane Smith"
              role: "Designer"
          YAML
          )

          # Create content directory and pages
          FileUtils.mkdir_p("content")
          File.write("content/post1.md", <<-MARKDOWN
          ---
          title: "Post 1"
          date: 2023-01-01
          authors: ["john-doe"]
          ---
          Content 1
          MARKDOWN
          )
          File.write("content/post2.md", <<-MARKDOWN
          ---
          title: "Post 2"
          date: 2023-01-02
          authors: ["john-doe", "jane-smith"]
          ---
          Content 2
          MARKDOWN
          )

          # Helper config/options
          options = Config::Options::BuildOptions.new(output_dir: "public")

          # Create builder
          builder = Builder.new
          builder.run(options)

          site = builder.site.not_nil!

          site.pages.size.should eq(2)

          # Verify site.data
          site.data.has_key?("authors").should be_true
          authors_data = site.data["authors"]
          authors_data["john-doe"]["name"].as_s.should eq("John Doe")
          authors_data["jane-smith"]["role"].as_s.should eq("Designer")

          # Verify site.authors
          site.authors.has_key?("john-doe").should be_true
          site.authors.has_key?("jane-smith").should be_true

          john = site.authors["john-doe"]
          john["name"].as_s.should eq("John Doe")
          john["pages"].as_a.size.should eq(2)       # Post 1 and Post 2
          john["twitter"].as_s.should eq("@johndoe") # Extra data merged

          jane = site.authors["jane-smith"]
          jane["name"].as_s.should eq("Jane Smith")
          jane["pages"].as_a.size.should eq(1)    # Post 2 only
          jane["role"].as_s.should eq("Designer") # Extra data merged
        end
      end
    end
  end
end
