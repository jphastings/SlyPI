spec = Gem::Specification.new do |s| 
  s.name = "SlyPI"
  s.version = "0.6"
  s.author = "JP Hastings-Spital"
  s.email = "slypi@projects.kedakai.co.uk"
  s.homepage = "http://projects.kedakai.co.uk/slypi/"
  s.platform = Gem::Platform::RUBY
  s.description = "Use SlyPIs (web-apis for sites that don't have them) in your ruby code with this simple gem"
  s.summary = "Use SlyPIs (web-apis for sites that don't have them) in your ruby code with this simple gem"
  s.files = ["slypi.rb"]
  s.require_paths = ["."]
  s.add_dependency("mechanize")
  s.has_rdoc = true
end
