#!/usr/bin/ruby

# Copyright (c) 2012 Stephan Kulow
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'optparse'
require 'rubygems'
#require 'rubygems/format'
require 'rubygems/specification'

opts = OptionParser.new("Usage: #{$0}")

provides=false
opts.on("-P", "--provides", "Output the provides of the package") do |val|
  provides=true
end
requires=false
opts.on("-R", "--requires", "Output the requires of the package") do |val|
  requires=true
end
file_match=".*/gems/[^/]*/specifications/.*\.gemspec$"
opts.on("-m", "--file-match REGEX", String,
	"Override the regex against which the input file names",
        "matched with the supplied regex") do |val|
  file_match=val
end
in_file=nil
opts.on("-g", "--gemspec FILE", String,
        "Take gemspec from FILE, not filename in STDIN",
        "Can be a .gem file or a .gemspec file") do |file|
  in_file=file
end
rest = opts.permute(ARGV)

unless provides || requires
  exit(0)
end

def fatal(msg)
  $stderr.puts msg
  exit 1
end

def register_gemspec_from_file(gemspecs, rubyabi, file)
  fatal "Couldn't read '#{file}'" unless File.readable? file

  case file
  when /\.gem$/
    gem = Gem::Format.from_file_by_path(file)
    fatal "Failed to load gem from '#{file}'" unless gem
    spec = gem.spec
  when /\.gemspec$/
    spec = Gem::Specification.load(file)
    fatal "Failed to load gem spec from '#{file}'" unless spec
  else
    fatal "'#{file}' must be a .gem or .gemspec file"
  end

  gemspecs << [ rubyabi, spec ]
end  

def rubyabi_from_path(path)
  m = path.match(%r{.*/gems/([^/]*)/.*})
  return m ? m[1] : RbConfig::CONFIG["ruby_version"]
end

gemspecs = Array.new

if in_file
  # This mode will not be used during actual rpm builds, but only by
  # gem packagers for debugging / diagnostics, so that they can
  # predict in advance what the dependencies will look like.
  rubyabi = rubyabi_from_path(in_file) || '$RUBYABI'
  register_gemspec_from_file(gemspecs, rubyabi, in_file)
else
  $stdin.each_line do |line|
    line.chomp!
    m = line.match(%r{#{file_match}$})
    if m
      register_gemspec_from_file(gemspecs, rubyabi_from_path(line), line)
    end
  end
end

gemspecs.each do |rubyabi, spec|
  if provides
    # old forms
    puts "rubygem-#{spec.name} = #{spec.version}"
    versions = spec.version.to_s.split('.')
    puts "rubygem-#{spec.name}-#{versions[0]} = #{spec.version}" if versions.length > 0
    puts "rubygem-#{spec.name}-#{versions[0]}_#{versions[1]} = #{spec.version}" if versions.length > 1
    puts "rubygem-#{spec.name}-#{versions[0]}_#{versions[1]}_#{versions[2]} = #{spec.version}" if versions.length > 2

    # version without ruby version - asking for trouble
    puts "rubygem(#{spec.name}) = #{spec.version}"
    if rubyabi
      puts "rubygem(#{rubyabi}:#{spec.name}) = #{spec.version}"
      puts "rubygem(#{rubyabi}:#{spec.name}:#{versions[0]}) = #{spec.version}" if versions.length > 0
      puts "rubygem(#{rubyabi}:#{spec.name}:#{versions[0]}.#{versions[1]}) = #{spec.version}" if versions.length > 1
      puts "rubygem(#{rubyabi}:#{spec.name}:#{versions[0]}.#{versions[1]}.#{versions[2]}) = #{spec.version}" if versions.length > 2
    end
  end

  if requires
    puts "ruby(abi) = #{rubyabi}" if rubyabi
    puts "rubygems" if rubyabi.to_f < 1.9
    spec.runtime_dependencies.each do |dep|
      dep.requirement.requirements.each do |r|
        if r.first == '~>'
          minversion = r.last.to_s.split('.')
          versions = minversion[0,minversion.length-1]
	  # ~> 2 is pretty nonsense, so avoid being tricked
	  if versions.length > 0
	    if minversion[minversion.length-1] == '0'
	      # ~> 1.2.0 is the same as >= 1.2 for rpm and it avoids problems when 1.2 is followed by 1.2.1
              minversion = versions
            end
            puts "rubygem(#{rubyabi}:#{dep.name}:#{versions.join('.')}) >= #{minversion.join('.')}"
          else
            puts "rubygem(#{rubyabi}:#{dep.name}) >= #{minversion.join('.')}"
          end
        elsif r.first == '!='
          # this is purely guessing, but we can't generate conflicts here ;(
          puts "rubygem(#{rubyabi}:#{dep.name}) > #{r.last}"
          #puts "rubygem(#{rubyabi}:#{dep.name}) < #{r.last}"
        else
          puts "rubygem(#{rubyabi}:#{dep.name}) #{r.first} #{r.last}"
        end
      end
    end
  end
end
