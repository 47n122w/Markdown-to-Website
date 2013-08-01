=begin
publish_html: pre_processor plugin to convert markdown to html

Copyright (C) 2013 Dale Brayden

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

require 'pathname'
require 'pre_processor'
require 'erb'
require 'rubygems'
require 'algorithms'

# See design-pandoc-runner.md for overall description.
#
# Additional options that can be passed via pp_main -o option:
#  n_recent : how many files to show on the recent index list
#
# External configuration:
#  Any of the source directories (i.e. the directories containing the
#  markdown files) can have a file names .pandoc_options. The top-level
#  source directory _must_ have such a file for this program to work
#  correctly. Subdirectories will inherit their parent directory's
#  .pandoc_options if one does not exist in the subdirectory.
#
#  There needs to be a directory somewhere under the :rootdir containing
#  templates named feed_template.xml and index_template.html for generating
#  the rss feed and page indices respectively. The directory must be
#  specified using -o template_dir=relative_dir_name .

class String
  def word_count
    self.split(%r{\W}).length
  end
end

PageSummary = Struct.new(:in_filename, :out_filename, :title,
                         :timestamp, :size, :description)
class PageSummary
  def printable_date
    timestamp.strftime('%b %d, %Y')
  end
  def pub_date
    # Should actually be date and time, with timezone
    printable_date
  end
  def sortable_date
    timestamp.strftime('%Y/%m/%d')
  end
  def weblink(base_dir)
    base_path = Pathname.new(base_dir)
    full_path = Pathname.new(out_filename)
    '/' + full_path.relative_path_from(base_path).to_s
  end
  def fetch_description(start_pattern)
    getting_text, word_count, lines = false, 0, []
    File.open(out_filename) { |f|
      f.readlines.each { |line|
        if getting_text
          lines << line
          word_count += line.word_count
          break if word_count > 200
        elsif line =~ start_pattern
          getting_text = true
        end
      }
    }
    self.description = lines.map { |line| line.chomp}.join("\n")
  end
end

OptionMap = Struct.new(:pattern, :options)

class PublishHtml < PreProcessor

  def initialize(s, t, options)
    super s, t, options
    @index_dir = []
    @index_recent = []
    @pandoc_opts = []
    @index_all = Containers::Heap.new
    @n_recent = options[:n_recent] || 10
    @n_recent = @n_recent.to_i
    @file_macros = {
      'ROOTDIR' => @options[:rootdir],
      'SOURCEROOT' => File.join(@options[:rootdir], @options[:sourcedir]),
      'TARGETROOT' => File.join(@options[:rootdir], @options[:targetdir]),
    }
    template_dirname = @options[:template_dir] || ''
    template_dir = File.join(@options[:rootdir], template_dirname)
    @web_base = @file_macros['TARGETROOT']
    @pandoc_opts_map = {}  # map source_dir to options
    @pandoc_binary = 'pandoc'
    @html_index_template = File.read(File.join(template_dir, 'index_template.html'))
    @xml_template = File.read(File.join(template_dir, 'feed_template.xml'))
    @section_index_template = File.read(
         File.join(template_dir, 'section_index_template.html'))
    [@html_index_template, @xml_template, @section_index_template].each { |t|
      if t.nil?
        $stderr.puts "Missing template"
        exit 1
      end
    }
    @min_interesting_size = 1200
    @verbose = options[:verbose]
  end

  def map_filename(filename)
    filename.sub(%r{\.md$}, '.html')
  end

  def handler(unused_in, unused_out, in_filename, out_filename)
    # update indices
    mtime = File.mtime(in_filename)
    size = File.size(in_filename)
    title = get_title(in_filename)
    summary = PageSummary.new(in_filename, out_filename, title,
                              mtime, size, title)
    @index_dir.last << summary
    if summary.size > @min_interesting_size
      @index_recent.last.push(mtime, summary)
      @index_recent.last.pop if @index_recent.last.size > @n_recent
    end
  end

  def get_title(filename)
    File.open(filename) { |f|
      meta = f.grep(/^% /)
      return filename if meta.length == 0
      return meta[0].strip.split('% ', 2)[1]
    }
  end

  def post_process(in_filename, out_filename)
    return if !File.exist?(out_filename)
    File.utime(File.atime(in_filename), File.mtime(in_filename),
               out_filename)
  end

  def begin_directory(source_dir, target_dir)
    # Look for .pandoc_options.
    @index_dir.push []
    @index_recent.push Containers::Heap.new
    @file_macros["SOURCEDIR"] = source_dir
    @file_macros["TARGETDIR"] = target_dir
    @pandoc_opts.push load_pandoc_opts(source_dir)
    $stderr.puts "Processing #{source_dir}"
  end

  def end_directory(source_dir, target_dir)
    index_dir = @index_dir.pop
    index_recent = @index_recent.pop
    pandoc_opts = @pandoc_opts.pop
    # Generate the index of all files in the current directory.
    generate_index(File.join(target_dir, '_section_index.html'),
                   @section_index_template, 'All Posts', 'section-index',
                   index_dir.sort { |x, y|
                     x.title.downcase <=> y.title.downcase
                   })
    index_dir.each { |p_s|
      pandoc_process(pandoc_opts, p_s.in_filename, p_s.out_filename)
    }
    recent_files = heap_to_a(index_recent).reverse
    # TODO(brayden): pass the start pattern as a flag
    recent_files.each { |file_summary|
      file_summary.fetch_description %r{<div id="content">}
    }
    recent_files.each { |x| @index_all.push(x.timestamp, x) }
    @index_all.pop while @index_all.size > @n_recent
    if is_root_dir
      # Generate the index of recent files site-wide.
      all_recent_files = heap_to_a(@index_all).reverse
      generate_index(File.join(target_dir, '_recent_index.html'),
                     @html_index_template, 'Recently Posted',
                     'section-index', all_recent_files)
      generate_index(File.join(target_dir, 'feed.xml'),
                     @xml_template, nil, nil, all_recent_files)
    else
      if @verbose
        $stderr.puts "Recent index for #{target_dir}:"
        $stderr.puts recent_files.map { | f | f.out_filename }
      end
      generate_index(File.join(target_dir, '_recent_index.html'),
                     @html_index_template, 'Recently Posted',
                     'section-index', recent_files)
    end
  end

  private

  def is_root_dir
    @index_dir.empty?
  end

  def pandoc_process(opts, in_file, out_file)
    # return if File.exist?(out_file) &&
    #  File.mtime(out_file) >= File.mtime(in_file)
    file_opts = pandoc_opts_for_file(opts, in_file)
    cmd = "#{@pandoc_binary} #{file_opts} -s #{in_file} -o #{out_file}"
    $stderr.puts out_file if @verbose
    `#{cmd}`
    $stderr.puts "Error processing #{in_file}" if !$?.success?
    File.utime(File.atime(in_file), File.mtime(in_file), out_file)
  end

  def load_pandoc_opts(source_dir)
    # Returns an array of OptionMap
    pandoc_opts_filename = File.join(source_dir, '.pandoc_options')
    parent_dir = File.dirname(source_dir)
    if File.exist? pandoc_opts_filename
      options = @pandoc_opts_map[source_dir] =
        load_pandoc_file(pandoc_opts_filename)
    elsif @pandoc_opts_map[parent_dir]
      options = @pandoc_opts_map[parent_dir]
      @pandoc_opts_map[source_dir] = options
    else
      return ''
    end
    expand_all_macros(source_dir, options)
  end

  def load_pandoc_file(filename)
    # Returns an array of OptionMap.
    # Sets @pandoc_binary if there is a pandoc: line.
    list = []
    cur_key = nil
    File.readlines(filename).map { |line| line.strip }.each { |line|
      if line =~ /^pandoc:\s*(.*)/
        @pandoc_binary = $1
        $stderr.puts "Using #{@pandoc_binary}"
        next
      end
      next if line =~ /\s*#/ || line.length == 0
      if line =~ %r{::(.*)::}
        cur_key = Regexp.new($1)
        list << OptionMap.new(cur_key, '')
        next
      end
      if cur_key.nil?
        cur_key = Regexp.new('.*')
        list << OptionMap.new(cur_key, '')
      end
      list.last.options << " #{line}"
    }
    list
  end

  def pandoc_opts_for_file(opts, filename)
    opts.each { |om| return om.options if filename =~ om.pattern }
    bail "No pandoc options found for #{filename}: #{opts}"
  end

  def bail(s)
    $stderr.puts s
    $stderr.puts "Exiting"
    exit 1
  end

  def expand_all_macros(source_dir, list)
    a = list.map { |om| om.clone }
    a.each { |om| om.options = expand_macros(source_dir, om.options)}
    a
  end

  def expand_macros(source_dir, s)
    @file_macros.each_pair { |name, value|
      s = s.gsub "$#{name}", value
    }
    s
  end

  def heap_to_a(a_heap)
    # The Collections:Heap class doesn't appear to have each,
    # so the normal enumerations don't work.
    # So we will destructively turn the heap into an array.
    a = []
    a_heap.size.times { |_| a << a_heap.pop }
    a
  end

  def generate_index(target_path, template_source, index_title, div_id,
                     p_s_list)
    template = ERB.new(template_source)
    begin
      File.open(target_path, 'w') { |f|
        f.puts template.result(binding)
      }
    rescue
      $stderr.puts "Can't generate index for #{target_path}"
    end
  end
end
