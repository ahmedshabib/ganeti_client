require 'rubygems'
require 'test/unit'
require 'shoulda'


lib_files = File.join(File.dirname(__FILE__), "..", "lib") 

# sub files need to be loaded as well ?
Dir.glob(File.join(lib_files, "**/*")).each do |file|
    require file
end
