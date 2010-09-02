require "rubygems"
require "rake"

begin
  require "jeweler"  
  Jeweler::Tasks.new do |gem|
    gem.name = "ganeti_client"
    gem.summary = "Google Ganeti Client"
    gem.description = "Google Ganeti RAPI client for Ruby"
    gem.rubyforge_project = "nowarning"
    gem.files = Dir["README","{lib}/**/*"]

    gem.version = "0.0.11"
    gem.author = "Michaël Rigart"
    gem.email = "michael@netronix.be"
    gem.homepage = "http://www.netronix.be"
    gem.add_dependency 'json'

  end
  Jeweler::GemcutterTasks.new
rescue
  puts "Jeweler or one of its dependencies is not installed."
end
