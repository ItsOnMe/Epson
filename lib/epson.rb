
# Actual Epson class
class Epson
  attr_accessor :model, :ip, :password
  attr_reader   :config

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


  def get_config
    return false  unless get_model() == :T88VI
    return JSON.parse(curl(@T88VI_API_URL))
  end


  def set_password(password='')
    @config[:NewPassword] = password
  end

  def set_administrator(admin, location)
    @config[:administrator] = {
      Administrator: admin,
      Location: location
    }
  end

  def set_sdp(url, interval, id, name)
    @config[:sdp] = {
      url: url,
      interval: interval.to_s,  # Printer wants a string, not a number
      id: id.to_s,
      name: name
    }
  end

  def set_status(url, interval, id, name)
    @config[:status] = {
      url: url,
      interval: interval.to_s,  # Printer wants a string, not a number
      id: id.to_s,
      name: name
    }
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
      log "Oh no!  Failed to update printer."
      log
      log "result:"
      pp  json
      log

      return false
    end


    log
    log "Configured!  Verifying..."
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
      log "Oh no!  There was an issue autoconfiguring the printer."
      log "Here are the values that failed to set correctly:"
      issues.each do |issue|
        log " > #{issue}"
      end

      log
      log "(Note: printer password remains unchanged)"
      log
      return false
    end


    ## For debugging.  In production, we will always update the password.
    if not @config[:NewPassword].present?
      log "Success!  Restarting..."
      return self.reset!
    end


    # ------ Update Password ------
    log "Setting password ..."

    data = {
      Setting: {
        NewPassword: @config[:NewPassword]
      }
    }

    # Construct and send API request
    url = @T88VI_API_URL
    url = url_add_put_data(url, data)

    $response = curl(url, :put)

    # Parse result
    json = JSON.parse($response)
    successful = json["message"].start_with?("Success")


    ##TODO: dry
    if not successful
      log "Oh no!  Error setting password"
      log "Please check the printer's configuration via its webconfig:"
      log "    Open your browser and visit: http://#{@ip}/"
      log
      Kernel::exit()
    end

    log "Success!"
    log
    log "Restarting printer..."

    successful = self.reset!


    ##TODO: dry
    if not successful
      log "Oh no!  Unable to restart the printer!"
      log "Please check the printer's configuration via its webconfig:"
      log "    Open your browser and visit: http://#{@ip}/"
      log
      Kernel::exit()
    end

    # New settings are only applid after a restart, including the password
    @password = @config[:NewPassword]

    return successful
  end




  # Fetch the current config, change it in-place, and send it back.
  def apply_T88VI_full_config!
    # Fetch the current config
    data = self.get_config
    settings = data["Setting"]  # Shortcut

    # Construct JSON
    if @config[:NewPassword]
      settings["Password"] = @config[:NewPassword]
      ##debug:
      settings["Password"] = "epson"
    end

    # The T88VI does not accept Administrator information.
    if @config[:administrator]
      # settings["Administrator"]  ||= {}
      settings["Administrator"]["Administrator"] = @config[:administrator][:Administrator]
      settings["Administrator"]["Location"]      = @config[:administrator][:Location]
    end

    if @config[:sdp]
      settings["ServerDirectPrint"]["Active"]    = "ON",
      settings["ServerDirectPrint"]["Url1"]      = @config[:sdp][:url]
      settings["ServerDirectPrint"]["Interval1"] = @config[:sdp][:interval]
      settings["ServerDirectPrint"]["ID"]        = @config[:sdp][:id]
      settings["ServerDirectPrint"]["Name"]      = @config[:sdp][:name]
      # Other ostensibly-required values:
      #   UseServerAuthentication: "OFF",
      #   UseProxy: "OFF",
      #   UseUrlEncode: "OFF",
      #   Password: ""
    end

    if @config[:status]
      settings["StatusNotification"]["Active"]    = "ON"
      settings["StatusNotification"]["Url1"]      = @config[:status][:url]
      settings["StatusNotification"]["Interval1"] = @config[:status][:interval]
      settings["StatusNotification"]["ID"]        = @config[:status][:id]
      settings["StatusNotification"]["Name"]      = @config[:status][:name]
    end

    # Construct API request
    url = @T88VI_API_URL
    url = url_add_put_data(url, data)

    # Request it!
    $response = curl(url, :put)

    # Parse result
    json = JSON.parse($response)
    successful = json["message"].start_with?("Success")

    log "result:"
    pp  json
    log ""


    return false  if not successful


    # Use new password
    # @password = @config[:NewPassword]

    log ""
    log "Re-fetching config..."
    config = self.get_config

    pp config


    # curl --digest --insecure -u epson:epson -X PUT https://10.0.0.95/webconfig/api/v1/webconfig.cgi -d "{\"Setting\":{\"ServerDirectPrint\":{\"Active\":\"OFF\"}}}"

    # return self.reset!

    return true
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
      log "---FATAL---"
      log "Failed to update #{endpoint}"
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
    command = "curl --silent --digest --insecure -u #{@username}:#{@password} #{type} #{url}"
    # log "cURL command: #{command}"

    # Handle the printer arbitrarily terminating connections.
    result = ""
    while result === ""
      result = `#{command}`
    end

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

