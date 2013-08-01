=begin
pre_processor: Base class for directory-transformation preprocessors.

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

require 'set'

# Base class for pre-processors.
# Derived classes must implement:
#   handler(in_handle, out_handle, in_filename, out_filename)
# and may override map_file(filename).
# Callers create an instance, then call process().
class PreProcessor
  def initialize(source_root, target_root, options)
    # Relevant options:
    #   :recurse - boolean
    #   :filepattern - regex
    # Derived classes might require additional options.
    @source_root, @target_root = source_root, target_root
    @options = options
    @processed_targets = Set.new
    @existing_targets = Set.new
  end

  def process
    process_dir(nil) { |s, t|
      td = File.dirname(t)
      mkdir_p(td) if not File.directory?(td)
      process_files s, t
    }
    redundant = @existing_targets - @processed_targets
    redundant.each { |path| rm path }
  end

  def map_filename(filename)
    # Override this to change the name of the target filename.
    filename
  end

  def post_process(in_filename, out_filename)
    # Override this to change properties of the target filename,
    # to set its modification date, for example. Use @options
    # to pass parameters. This is thread hostile.
  end

  def begin_directory(source_dir, target_dir)
    # Override this to do special handling when beginning to process
    # a directory.
  end

  def end_directory(source_dir, target_dir)
    # Override this to do special handling when completing processing
    # a directory.
  end

  private

  def process_dir(rel_dir, &block)
    sub_dirs = []
    source_dir = rel_dir ? File.join(@source_root, rel_dir) : @source_root
    target_dir = rel_dir ? File.join(@target_root, rel_dir) : @target_root
    mark_target_files target_dir, @options[:remove_target_dir_files]
    self.begin_directory(source_dir, target_dir)
    Dir.foreach(source_dir) { |filename|
      next if filename == '.' || filename == '..'
      fullpath = File.join(source_dir, filename)
      if @options[:recurse] && File.directory?(fullpath)
        sub_dirs << filename
      elsif fullpath =~ @options[:filepattern]
        target_path = File.join(target_dir, map_filename(filename))
        yield fullpath, target_path
        @processed_targets << target_path
      end
    }
    sub_dirs.each { |sub_dir|
      new_dir = rel_dir ? File.join(rel_dir, sub_dir) : sub_dir
      process_dir(new_dir, &block)
    }
    self.end_directory(source_dir, target_dir)
  end

  def process_files(s_filename, t_filename)
    if !@options[:open_files]
      handler nil, nil, s_filename, t_filename
    else
      File.open(s_filename) { |in_handle|
        File.open(t_filename, 'w') { |out_handle|
          handler in_handle, out_handle, s_filename, t_filename
        }
      }
    end
    post_process s_filename, t_filename
  end

  def mark_target_files(dir, pattern)
    return if !pattern || !File.directory?(dir)
    Dir.foreach(dir) { |filename|
      next if filename == '.' || filename == '..'
      if filename =~ pattern
        @existing_targets << File.join(dir, filename)
      end
    }
  end
end
