require 'capybara/rack_test/driver'
require 'mechanize'

class Capybara::Mechanize::Browser < Capybara::RackTest::Browser
  extend Forwardable
  
  def_delegator :agent, :scheme_handlers
  def_delegator :agent, :scheme_handlers=
  
  def initialize(app = nil, options)
    @agent = ::Mechanize.new
    @agent.redirect_ok = false
    
    super
  end
  
  def reset_cache!
    @agent.cookie_jar.clear!
    super
  end
  
  def reset_host!
    @last_remote_host = nil
    @last_request_remote = nil
    super
  end
  
  def current_url
    last_request_remote? ? remote_response.current_url : super
  end
  
  def last_response
    last_request_remote? ? remote_response : super
  end
  
  # TODO see how this can be cleaned up
  def follow_redirect!
    unless last_response.redirect?
      raise "Last response was not a redirect. Cannot follow_redirect!"
    end
  
    location = if last_request_remote?
        remote_response.page.response['Location'] 
      else
        last_response['Location']
      end
    
    get(location)
  end
  
  def get(url, params = {}, headers = {})
    if remote?(url)
      process_remote_request(:get, url, params)
      follow_redirects!
    else
      register_local_request
      super
    end
  end
  
  def visit(url, params = {})
    if remote?(url)
      process_remote_request(:get, url, params)
      follow_redirects!
    else
      register_local_request
      super
    end
  end
  
  def submit(method, path, attributes)
    path = request_path if not path or path.empty?
    if remote?(path)
      process_remote_request(method, path, attributes)
      follow_redirects!
    else
      register_local_request
      super
    end
  end

  def follow(method, path, attributes = {})
    return if path.gsub(/^#{request_path}/, '').start_with?('#')

    if remote?(path)
      process_remote_request(method, path, attributes)
      follow_redirects!
    else
      register_local_request
      super
    end

  end
  
  def post(url, params = {}, headers = {})
    if remote?(url)
      process_remote_request(:post, url, post_data(params), headers)
    else
      register_local_request
      super
    end
  end
  
  def post_data(params)
    params.inject({}) do |memo, param|
      case param
      when Hash
        param.each {|attribute, value| memo[attribute] = value }
        memo
      when Array
        case param.last
        when Hash
          param.last.each {|attribute, value| memo["#{param.first}[#{attribute}]"] = value }
        else
          memo[param.first] = param.last
        end
        memo
      end
    end
  end
  
  def put(url, params = {}, headers = {})
    if remote?(url)
      process_remote_request(:put, url)
    else
      register_local_request
      super
    end
  end
  
  def delete(url, params = {}, headers = {})
    if remote?(url)
      process_remote_request(:delete, url, params, headers)
    else
      register_local_request
      super
    end
  end
  
  def remote?(url)
    if !Capybara.app_host.nil? 
      true
    elsif Capybara.default_host.nil?
      false
    else
      host = URI.parse(url).host
      
      if host.nil? && last_request_remote?
        true
      else
        !(host.nil? || Capybara.default_host.include?(host))
      end
    end
  end
  
  attr_reader :agent
  
  private
  
  def last_request_remote?
    !!@last_request_remote
  end
  
  def register_local_request
    @last_remote_host = nil
    @last_request_remote = false
  end
  
  def process_remote_request(method, url, *options)
    if remote?(url)
      remote_uri = URI.parse(url)
  
      if remote_uri.host.nil?
        remote_host = @last_remote_host || Capybara.app_host || Capybara.default_host
        url = File.join(remote_host, url)
        url = "http://#{url}" unless url.include?("http")
      else
        @last_remote_host = "#{remote_uri.host}:#{remote_uri.port}"
      end
      
      reset_cache!
      @agent.send *( [method, url] + options)
        
      @last_request_remote = true
    end
  end
  
  def remote_response
    ResponseProxy.new(@agent.current_page) if @agent.current_page
  end
  
  class ResponseProxy
    extend Forwardable
    
    def_delegator :page, :body
    
    attr_reader :page
    
    def initialize(page)
      @page = page
    end
    
    def current_url
      page.uri.to_s
    end
    
    def headers
      # Hax the content-type contains utf8, so Capybara specs are failing, need to ask mailinglist  
      headers = page.response
      headers["content-type"].gsub!(';charset=utf-8', '') if headers["content-type"]
      headers
    end
  
    def status
      page.code.to_i
    end    
  
    def redirect?
      [301, 302].include?(status)
    end
    
  end 
   
end
