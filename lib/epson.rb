# Actual Epson class

require 'colorize'


class Epson
  attr_accessor :model, :password
  attr_reader   :config, :ip

  class ConnectionError < IOError; end


  def initialize(model, ip, password='epson')
    @model    = model || :T88VI
    @ip       = ip
    @username = "epson"   # epson. epson never changes.
    @password = password
    @config   = Hash.new

    @T88VI_API_URL   = "https://#{ip}/webconfig/api/v1/webconfig.cgi"
    @T88VI_RESET_URL = "https://#{ip}/webconfig/api/v1/reset.cgi"

    # API Constants
    @T88V_API_ENDPOINTS = {
      administrator:        "administrator.cgi",
      server_direct_print:  "server_direct_print.cgi",
      status_notification:  "status_notification.cgi",
      password:             "password.cgi",
    }
  end

  def ip= ip
    @ip = ip
    @T88VI_API_URL   = "https://#{ip}/webconfig/api/v1/webconfig.cgi"
    @T88VI_RESET_URL = "https://#{ip}/webconfig/api/v1/reset.cgi"
  end


  def test_connection
    return test_connection_T88V  if get_model() == :T88V
    return test_connection_T88VI if get_model() == :T88VI
    raise RuntimeError, "Incorrect printer model"
  end


  def get_config
    return false  unless get_model() == :T88VI
    return JSON.parse(curl(@T88VI_API_URL))
  end


  def set_password password:''
    @config[:NewPassword] = password
  end

  def set_administrator(admin:nil, location:nil)
    @config[:administrator] ||= {}
    @config[:administrator].merge!({
      Administrator: admin,
      Location: location
    }.compact)
  end

  def set_epos(active:nil)
    active = (active ? "ON" : "OFF")  unless active.nil?

    @config[:epos] ||= {}
    @config[:epos].merge!({
      active:   active
    }.compact)
  end

  def set_sdp(active:nil, url:nil, interval:nil, id:nil, name:nil)
    active = (active ? "ON" : "OFF")  unless active.nil?

    @config[:sdp] ||= {}
    @config[:sdp].merge!({
      active:   active,
      url:      url,
      interval: interval,
      id:       id,
      name:     name
    }.compact)
  end

  def set_status(active:nil, url:nil, interval:nil, id:nil, name:nil)
    active = (active ? "ON" : "OFF")  unless active.nil?

    @config[:status] ||= {}
    @config[:status].merge!({
      active:   active,
      url:      url,
      interval: interval,
      id:       id,
      name:     name
    }.compact)
  end

  # ------

  def apply!
    return apply_T88V!  if get_model() == :T88V
    return apply_T88VI! if get_model() == :T88VI
  end

  # ------

  def reset!
    # Only works for the VI model
    return false  unless get_model() == :T88VI

    $response = curl(@T88VI_RESET_URL)
    response  = JSON.parse($response)
    return false  unless response['message'] == "Success"

    sleep(30)  # Wait for the printer to restart
    return true
  end




  private


  def test_connection_T88VI
    # Fetch config
    get_config
    true
  rescue
    false
  end


  def test_connection_T88V
    # Fetch SDP config data
    curl T88V_api_url(T88V_endpoint_url(:set, :server_direct_print))
    true
  rescue
    false
  end


  # Update only the new settings
  def apply_T88VI!
    data     = { Setting: Hash.new }
    settings = data[:Setting]  # Shortcut

    # ------ Construct JSON ------
    if @config[:administrator]
      # The T88VI does not accept Administrator information.
      settings[:Administrator] = @config[:administrator].extract(:Administrator, :Location)
    end

    if @config[:sdp]
      settings[:ServerDirectPrint] = {
        Active:    "ON",
        Url1:      @config[:sdp][:url],          # Set the first of three URLs and Intervals
        Interval1: @config[:sdp][:interval],
        ID:        @config[:sdp][:id],
        Name:      @config[:sdp][:name],
      }
    end

    if @config[:status]
      settings[:StatusNotification] = {
        Active:    "ON",
        Url:       @config[:status][:url],       # There's only a single URL and Interval
        Interval:  @config[:status][:interval],
        ID:        @config[:status][:id],
        Name:      @config[:status][:name]
      }
    end

    if settings.empty?
      log "Nothing to update."
      return false
    end


    # ------ Construct and send API request ------
    url = @T88VI_API_URL
    url = url_add_put_data(url, data)

    $response = curl(url, :put)

    # Parse result
    json = JSON.parse($response)
    successful = json["message"].start_with?("Success")


    if not successful
      log "Oh no!  Failed to update printer.".red
      log
      log "result:"
      pp  json
      log

      return false
    end

    unless silent
      log "Configured!".cyan
      log
      log "Verifying..."
    end
    printer_config = self.get_config["Setting"]


    # ------ Verify config ------

    issues = []
    if @config[:sdp].present?
      issues.push "ServerDirectPrint -- Active"     if printer_config["ServerDirectPrint"]["Active"]    != "ON"
      issues.push "ServerDirectPrint -- Url1"       if printer_config["ServerDirectPrint"]["Url1"]      != @config[:sdp][:url]
      issues.push "ServerDirectPrint -- Interval1"  if printer_config["ServerDirectPrint"]["Interval1"] != @config[:sdp][:interval]
      issues.push "ServerDirectPrint -- ID"         if printer_config["ServerDirectPrint"]["ID"]        != @config[:sdp][:id]
      issues.push "ServerDirectPrint -- Name"       if printer_config["ServerDirectPrint"]["Name"]      != @config[:sdp][:name]
    end
    if @config[:status].present?
      issues.push "StatusNotification -- Active"    if printer_config["StatusNotification"]["Active"]   != "ON"
      issues.push "StatusNotification -- Url"       if printer_config["StatusNotification"]["Url"]      != @config[:status][:url]
      issues.push "StatusNotification -- Interval"  if printer_config["StatusNotification"]["Interval"] != @config[:status][:interval]
      issues.push "StatusNotification -- ID"        if printer_config["StatusNotification"]["ID"]       != @config[:status][:id]
      issues.push "StatusNotification -- Name"      if printer_config["StatusNotification"]["Name"]     != @config[:status][:name]
    end


    if issues.present?
      log "Oh no!  There was an issue autoconfiguring the printer.".red
      log "Here are the values that failed to set correctly:".light_black
      issues.each do |issue|
        log " > ".red + "#{issue}".light_black
      end

      ##+ Cannot update password via API yet
      # log
      # log "(Note: printer password remains unchanged)"
      log
      return false
    end


    ## For debugging.  In production, we will always update the password.
    if not @config[:NewPassword].present?
      log "Success!".cyan
      log
      log "Restarting printer..."
      return self.reset!
    end


    ##+ Cannot update password via API yet
    # ------ Update Password ------
    # log "Setting password..."

    # data = {
    #   Setting: {
    #     NewPassword: @config[:NewPassword]
    #   }
    # }

    # # Construct and send API request
    # url = @T88VI_API_URL
    # url = url_add_put_data(url, data)

    # $response = curl(url, :put)

    # # Parse result
    # json = JSON.parse($response)
    # successful = json["message"].start_with?("Success")


    # ##TODO: dry
    # if not successful
    #   log "Oh no!  Error setting password"
    #   log "Please check the printer's configuration via its webconfig:"
    #   log "    Open your browser and visit: http://#{@ip}/"
    #   log
    #   Kernel::exit()
    # end

    unless silent
      log "Success!".cyan
      log
      log "Restarting printer..."
    end

    successful = self.reset!


    ##TODO: dry
    if not successful
      log "Oh no!  Unable to restart the printer!".red
      log "Please restart it manually, and check the configuration via its webconfig:"
      log "    Open your browser and visit: http://#{@ip}/"
      log
      Kernel::exit()
    end

    ##+ Cannot update password via API yet
    # New settings are only applied after a restart
    # @password = @config[:NewPassword]

    return successful
  end




  def apply_T88V!
    updated = false

    # Apply Password
    if @config[:NewPassword]
      T88V_update :password, @config.extract(:NewPassword)
      updated = true
    end

    # Apply Administrator
    if @config[:administrator]
      T88V_update :administrator, @config[:administrator].extract(:Administrator, :Location)
      updated = true
    end

    # Apply Server Direct Print
    if @config[:sdp]
      data = {
        Use:       "Enable",
        URL1:      @config[:sdp][:url],
        Interval1: @config[:sdp][:interval],
        Name:      @config[:sdp][:name],
        ID:        @config[:sdp][:id]
      }

      T88V_update :sdp, data
      updated = true
    end

    # Apply Status Notification
    if @config[:status]
      data = {
        Use:       "Enable",
        URL1:      @config[:status][:url],
        Interval1: @config[:status][:interval],
        Name:      @config[:status][:name],
        ID:        @config[:status][:id]
      }

      T88V_update :status, data
      updated = true
    end

    # Finished!

    unless updated
      log "Nothing to update."
      return false
    end

    log "Done!"
    true
  end


  # Call the printer's API to update specific values
  def T88V_update(endpoint, data={})
    log "Updating #{endpoint}..."
    pp data

    # Construct url
    url = T88V_api_url(T88V_endpoint_url(:set, endpoint))
    url = url_add_post_data(url, data)

    log "URL: #{url}"

    # Call via curl
    $result = result = curl(url)

    pp result

    # Parse the response and display success/failure
    json = JSON.parse(result)
    if json['response']['success'] == 'true'
      log " | Success!"
      log

    elsif json['response']['success'] == 'false'
      log
      log
      log "---FATAL---".black.on_red
      log "Failed to update #{endpoint}".red
      log
      log "URL: #{url}"
      log
      log result
      Kernel::exit()
    end
  end



  def T88V_endpoint_url(type, endpoint)
    url = @T88V_API_ENDPOINTS[endpoint]
    raise ArgumentError, "endpoint_url: Invalid endpoint"  if url.nil?

    return "config_#{url}"  if type == :get
    return "set_#{url}"     if type == :set
  end


  def T88V_api_url(endpoint)
    "http://#{@ip}/webconfig/#{endpoint}?format=json"
  end


  def url_add_put_data(url, data)
    "#{url} -d '#{data.to_json}'"
  end


  def url_add_post_data(url, data)
    data.each do |k,v|
      url += " -d #{k}=#{v}"  ##! May break when setting blank ("") values
    end

    url
  end


  def curl(url, type=:get)
    type = "-X #{type.upcase.to_s}"
    command = "curl --silent --connect-timeout 20 --digest --insecure -u #{@username}:#{@password} #{type} #{url}"

    # Handle the printer arbitrarily terminating connections.
    # (Only retry within 6 seconds to allow for timeouts and connection failures)
    result = ""
    start = Time.now
    while result === "" and Time.now < start+6
      result = `#{command}`
    end

    # If there's still no data, raise an exception
    raise ConnectionError  if result === ""

    return result
  end


  # Simple logger
  def log(str=nil)
    printf "#{str}\n"
  end


  def get_model
    #TODO: autodetermine model from api
    return @model.to_sym
  end

end

