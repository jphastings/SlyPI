# = SlyPI
# This gem accepts a SlyPI (a glorified YAML settings file) and will give you an object with the SlyPI specified methods.
#
# The aim of these is to create simple SlyPI files to collect information from websites that don't have web-apis. Essentially its formalized screen-scraping, not entirely responsible, but its been useful to me before!
#
# If a website changes its structure (breaking any screen scraping procedures) only the SlyPI settings file need be updated, and and depending applications will go back to working as normal.
#
# == Example
#   require 'slypi'
#   s = SlyPI.new("tv.com.slypi") # From here: http://github.com/jphastings/SlyPI-examples
#   p s.slypi_methods # ["SearchShows","Episodes","EpisodeDetails","ShowDetails"]
#   p s.SearchShows(:q => "Fawlty Towers")
#   # {"Shows"=>[{"showid"=>"3453", "Title"=>"Fawlty Towers", "Description"=>"The genesis of ... and so on
#   p s.ShowDetails(:showid => 3453)
#   # {"Genres"=>"Comedy", "Title"=>"Fawlty Towers", "Description"=> ... and so on
# At the moment there's no obvious way to find out what parameters are required by each slypi_method, but the slypi settings files are human readable, everything is the same as it is in there, so you should be able to work out what to call.
#
# == Warning
# Screen scraping in this fashion is generally speaking not allowed by websites. Use this at your own risk, and be nice - don't try and make hundreds of calls in one go.
#
# == Getting in Touch
# githib::	http://github.com/jphastings
# twitter::	@jphastings
# facebook::	http://facebook.com/profile.php?id=36800401
# email::	slypi@projects.kedakai.co.uk

require 'yaml'
require 'rubygems'
require 'mechanize'

# The SlyPI class. It has only two permanent methods, the others are dynamically generated by the SlyPI settings file specified at initialization.
class SlyPI
  attr_reader :service, :version, :author, :site, :description, :slypi_methods
  
  # Give it a file (in the slypi format) and your class will be generated for you!
  #
  # In the future I may get this to accept string settings files too (at the moment, it must be a file)
  def initialize(slypi_file)
    settings = nil
    @agent = WWW::Mechanize.new
    
    if slypi_file =~ /^http:\/\/(.*\.slypi)$/
      cachefname = $1.gsub(/[^a-zA-Z0-9\.-]+/,"_")
      if not File.exists?(cachefname)
        open(cachefname,"w") do |file|
          @agent.get(slypi_file) do |page|
            file.write page.body
          end
        end
      end
      slypi_file = cachefname
    end
    
    raise "File not found" if not File.exists?(slypi_file)
    open(slypi_file) do |f|
      settings = YAML.load(f)
    end
    
    @service = settings['About']['Name']
    @service.freeze
    @version = settings['About']['Version']
    @version.freeze
    @author = settings['About']['Author']
    @author.freeze
    @site = settings['About']['Site']
    @site.freeze
    @description = settings['About']['Description']
    @description.freeze
    @slypi_methods = []
    @authenticated = true
    if not settings['Login'].nil?
      @authenticated = false
      @slypi_methods.push("login")
      eval("def login( options = {} )
        raise \"Please specify a hash of the function terms\" if not options.is_a?(Hash)
        details = #{settings['Login'].inspect}
        if send(\"run_function\",details,options)['Success']
          @authenticated = true
          return true
        else
          $stderr.puts \"Login Failed\"
          return false
        end
      end")
    end
    
    settings['Functions'].each do |function_name,details|
      if function_name =~ /^[0-9a-zA-Z]+$/
        @slypi_methods.push(function_name)
        eval("def #{function_name}( options = {} )
          raise \"Please specify a hash of the function terms\" if not options.is_a?(Hash)
          raise \"You're not authenticated.\" if not @authenticated
          details = #{details.inspect}
          return send(\"run_function\",details,options)
        end")
      else
        $stderr.puts "The method '#{function_name}' is not a valid SlyPI method name. Please check your api file!"
      end
    end
    @slypi_methods.freeze
  end
  
  # If the loaded SlyPI requires authentication this will tell you if everything is ready to proceed
  def authenticated?
    @authenticated
  end
  
  # Just a standard inspect method at the moment. In the future it will allow you to inspect the dynamically generated methods to find out what they require and other such information
  def inspect(conditions = nil)
    if conditions.nil?
      "SlyPI #{@service} class"
    else
      if @methods.include?(conditions[:method])
        # TODO: give info about what paramters are required about the given message
        puts "details about this method here"
        return nil
      else
        raise "I don't know what part of this SlyPI you want to inspect"
      end
    end
  end
  
  private
  def run_function(spec,parameters)
    # Check to make sure the parameters meet the requirements. Raise an error if they don't (they're required)
    if not spec['requires'].nil?
      spec['requires'].each do |spec_name,details|
        raise "Required parameter '#{spec_name}' does not need the requiremens ('#{parameters[spec_name.to_sym]}' should fit regexp: #{details['format']})" if parameters[spec_name.to_sym].to_s.match(Regexp.new(details['format'],Regexp::MULTILINE)).nil?
      end
    end
    # Remove any optional parameters that don't meet requirements, append defaults to those that aren't specified
    if not spec['optional'].nil?
      spec['optional'].each do |spec_name,details|
        parameters[spec_name.to_sym] = nil if not parameters[spec_name.to_sym].nil? and parameters[spec_name.to_sym].to_s.match(Regexp.new(details['format'],Regexp::MULTILINE)).nil?
        parameters[spec_name.to_sym] = details['default'] if parameters[spec_name.to_sym].nil?
      end
    end
    
    url = subst(spec['request']['url'],parameters)
    begin
      case spec['request']['method']
      when "POST"
        p opts = Hash[*spec['request']['data'].collect{ |opt| [opt[0],subst(opt[1],parameters)] }.flatten]
        page = @agent.post(url,opts)
      else # Includes GET
        page = @agent.get(url)
      end
    rescue
      $stderr.puts "We've experienced an error attempting to get the information from '#{url}'. More information follows."
      raise
    end
    output = traverse(page.parser,spec['returns'],parameters)
    output['_sourceUrl'] = url
    return output
  end
  
  def traverse(root,items,params)
    output = {}
    items.each do |item|
      if item[1].include? "_base"
        cont = item[1].reject{|key,val| key == "_base"}
        output[item[0]] = root.xpath(subst(item[1]['_base'],params)).collect{ |hits| traverse(hits,cont,params) }
      else
        begin
          el = root.xpath(subst(item[1]['xpath'],params))
          if not item[1]['regex'].nil?
            output[item[0]] = (el.is_a?(String) or el.length < 2) ?
              el.inner_text.strip.match(Regexp.new(subst(item[1]['regex'],params),Regexp::MULTILINE))[1] :
              el.collect{ |e|
                e.inner_text.strip.match(Regexp.new(subst(item[1]['regex'],params),Regexp::MULTILINE))[1]
              }
          elsif not item[1]['matches'].nil?
            output[item[0]] = (el.is_a?(String) or el.length < 2) ?
              (not el.inner_text.strip.match(Regexp.new(subst(item[1]['matches'],params),Regexp::MULTILINE)).nil?) :
              el.inject(true){ |e|
                (not e.inner_text.strip.match(Regexp.new(subst(item[1]['matches'],params),Regexp::MULTILINE)).nil?)
              }
          else
            output[item[0]] = (el.is_a?(String) or el.length < 2) ? el.inner_text.strip : el.collect{|e| e.inner_text.strip}
          end
        rescue NoMethodError
        end
      end
    end
    return output
  end
  
  def subst(input,params)
    return input if input.match(/%\{[a-zA-Z0-9]+\}/).nil?
    string = input
    params.each do |param|
      string = string.gsub(/%\{#{param[0]}\}/,URI::encode(param[1].to_s))
    end
    return string
  end
end