=begin
pp_main: Driver for running PreProcessor derived classes.

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

require 'pre_processor'

# This is the driver for running text pre processors. The
# PreProcessor class in pre_processor.rb defines the general
# strategy. That class must be implemented by derived classes.
# The name of the derived class is passed as a command-line
# parameter to this program: --processor MyPreProcessor. The
# derived class must be in a source file whose name is the
# underscored version of the classs name: my_pre_processor.rb
# in this example.
if __FILE__ == $0
  require 'optparse'
  require 'fileutils'


  def bail(s)
    $stderr.puts s
    exit 1
  end

  def classname_to_rb_filename(classname)
    filebase = classname.gsub(%r{([a-z])([A-Z])}, '\1_\2').downcase
    "#{filebase}.rb"
  end

  def load_class(classname)
    filename = classname_to_rb_filename(classname)
    load filename
    Object.const_get classname.to_sym
  end

  options = {}
  options[:filepattern] = '.*\.txt$'
  options[:execute] = false
  options[:open_files] = true
  options[:verbose] = false
  optparse = OptionParser.new { |opts|
    opts.banner = "Usage: #{__FILE__} [options] file ..."
    opts.on('-d', '--rootdir DIR', 'Files root') { |dirname|
      options[:rootdir] = dirname
      $stderr.puts "rootdir=#{dirname}"
    }
    opts.on('-t', '--targetdir DIR', 'Target dir') { |reldirname|
      options[:targetdir] = reldirname
      $stderr.puts "targetdir=#{reldirname}"
    }
    opts.on('-s', '--sourcedir DIR', 'Source dir') { |reldirname|
      options[:sourcedir] = reldirname
      $stderr.puts "sourcedir=#{reldirname}"
    }
    opts.on('-x', '--execute', 'Really run') { options[:execute] = true }
    opts.on('-r', '--recurse', 'Recurse directories') { options[:recurse] = true }
    opts.on('-n', '--no_file_open', 'Do not open files') {
      options[:open_files] = false
    }
    opts.on('-e', '--filepattern PATTERN', 'File pattern') { |pattern|
      options[:filepattern] = pattern
      $stderr.puts "filepattern=#{pattern}"
    }
    opts.on('-k', '--remove_target_dir_files PATTERN') { |pattern|
      options[:remove_target_dir_files] = pattern
    }
    opts.on('-p', '--processor CLASSNAME', 'Process class') { |classname|
      options[:processor] = load_class(classname)
    }
    opts.on('-o', '--extra_options KV_PAIRS',
            'Comma separated key=value pairs') { |list|
      items = list.split(',')
      items.each {|item|
        kv = item.split('=', 2)
        if kv.length == 1
          options[kv[0].to_sym] = true
        else
          options[kv[0].to_sym] = kv[1]
        end
      }
    }
    opts.on('-v', '--verbose', 'Verbose output') { options[:verbose] = true }
    opts.on('-h', '--help', 'Display this') { puts opts; exit }
  }
  optparse.parse!
  options[:filepattern] = Regexp.new(options[:filepattern])
  if options[:remove_target_dir_files]
    options[:remove_target_dir_files] = Regexp.new(
        options[:remove_target_dir_files])
  end
  if options[:execute]
    $stderr.puts "For realz!"
    include FileUtils::Verbose
  else
    $stderr.puts "Dry run only!"
    include FileUtils::DryRun
  end

  bail('process class required') if not options[:processor]
  bail('rootdir required') if not options[:rootdir]
  bail('targetdir required') if not options[:targetdir]
  bail('sourcedir required') if not options[:sourcedir]
  full_target_root = File.join(options[:rootdir], options[:targetdir])
  $stderr.puts "full target root = #{full_target_root}"
  bail("no such directory: #{full_target_root}") if !File.exist?(full_target_root)
  full_source_root = File.join(options[:rootdir], options[:sourcedir])
  $stderr.puts "full source root = #{full_source_root}"
  bail("no such directory: #{full_source_root}") if !File.exist?(full_source_root)
  # main processing starts here.
  processor = options[:processor]
  p = processor.new(full_source_root, full_target_root, options)
  p.process
end
