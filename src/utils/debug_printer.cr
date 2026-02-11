require "../models/site"
require "../models/page"
require "../models/section"
require "colorize"

module Hwaro
  module Utils
    module DebugPrinter
      class Node
        property name : String
        property children : Hash(String, Node)
        property pages : Array(Models::Page)
        property section : Models::Section?

        def initialize(@name : String)
          @children = {} of String => Node
          @pages = [] of Models::Page
        end
      end

      def self.print(site : Models::Site, io : IO = STDOUT)
        root = Node.new("root")

        # Build tree from pages
        site.pages.each do |page|
          # Determine path parts based on section
          # If page.section is empty, it's at root
          parts = page.section.split("/").reject(&.empty?)

          current = root
          parts.each do |part|
            current = current.children[part] ||= Node.new(part)
          end

          current.pages << page
        end

        # Build tree from sections (to capture sections that might have no pages but exist)
        site.sections.each do |section|
          # Section path is e.g. "blog/_index.md" -> dirname "blog"
          dir = Path[section.path].dirname
          dir = "" if dir == "."

          parts = dir.split("/").reject(&.empty?)

          current = root
          parts.each do |part|
            current = current.children[part] ||= Node.new(part)
          end

          current.section = section
        end

        io.puts "\nSite Structure (Debug):".colorize(:cyan).mode(:bold)
        print_node(root, "", true, io)
        io.puts ""
      end

      private def self.print_node(node : Node, prefix : String, is_root : Bool, io : IO)
        unless is_root
          # Determine label
          label = node.name
          if section = node.section
            label += " (Section: #{section.title})"
            io.puts "#{prefix}#{label}".colorize(:blue).mode(:bold)
          else
            label += " (Dir)"
            io.puts "#{prefix}#{label}".colorize(:blue)
          end
        end

        indent = is_root ? "" : prefix + "  "

        # Print pages
        node.pages.sort_by!(&.title).each do |page|
          io.puts "#{indent}- #{page.title} (#{page.path})".colorize(:green)
        end

        # Print children
        sorted_children = node.children.keys.sort
        sorted_children.each do |key|
          print_node(node.children[key], indent, false, io)
        end
      end
    end
  end
end
