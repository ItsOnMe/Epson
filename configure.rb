# Epson printer automatic configuration!

# Caveats:
#  * cannot set blank values on the printer


require 'pp'
require 'rest-client'  # for communicating with the server
require 'json'


require './lib/patches.rb'
require './lib/epson.rb'
require './lib/shell_utilities.rb'



class Menu
  def initialize
    @TOKEN = {
      QA:         "0QampoLwiYRnlsGLmJDIwiRTBAyjSHeRrObF6QTRw",
      PRODUCTION: "QFvwqlUQ1VMtT0td9G1iwl4SENEN2fCEZbhjmVHKaw"
    }
  end


  # Begin menu loop
  def start
    # Initial step
    step = :mode

    while step != :done
      clear_screen
      display_menu

      step = case(step)
      when :mode
        step_mode
      when :confirm_mode
        step_mode_confirm
      when :model
        step_model
      when :ip
        step_ip
      when :merchant
        step_merchant
      when :autoconfigure
        step_autoconfigure
      when :done
        step_done
      end

    end
  end



  def display_menu
    clear_screen

    # Add mode info, if present
    mode_string = ""
    if @mode.present?
      # Right-align
      spacing  = " " * (6 + (10 - @mode.length))

      mode_string = spacing + "[ Mode: #{@mode.upcase.to_s} ]"
    end

    # Display header
    printf " ☼ ItsOnMe  --  Epson Printer Configuration #{mode_string}\n"
    printf "----------------------------------------------------------------------\n"

    # Display printer info, if present.
    printer_info = []
    printer_info << "Model #{@model}"  if @model.present?
    printer_info << "IP: #{@ip}"       if @ip.present?
    printf printer_info.join(", ")

    printf "\n\n"
  end



  # ============ Steps ============ #


  # --- Step: Mode ------------
  def step_mode
    @mode = nil
    @mode = prompt_mode
    :confirm_mode
  end


  # --- Step: Mode (confirm) ------------
  def step_mode_confirm
    choice = prompt("You picked #{@mode.upcase}. Are you sure?", ['yes', 'no'], 'yes')

    if choice == 'no'
      # Clear mode
      @mode = nil
      return :mode
    end

    :model
  end


  # --- Step: Model ------------
  def step_model
    @model = prompt_model
    :ip
  end


  # --- Step: IP ------------
  def step_ip
    @ip = prompt_ip
    :merchant
  end


  # --- Step: Merchant ------------
  def step_merchant
    valid = false
    until valid
      merchant_id = prompt_merchant
      valid = verify_merchant(@mode, merchant_id)
    end

    choice = prompt("Is this correct?", ['yes', 'no'])

    # Incorrect? repeat this step.
    return :merchant  if choice == 'no'


    @merchant_id = merchant_id
    :autoconfigure
  end


  # --- Step: Autoconfigure ------------
  def step_autoconfigure
    printf "Alright, let's configure the printer!\n\n"

    password = prompt_password

    autoconfigure(@mode, @merchant_id, @ip, password)

    printf "\n\n"

    # Cleanup
    @ip = @merchant_id = nil

    choice = prompt("Configure another?", ['yes', 'no'], 'yes')
    return :model  if choice == 'yes'
    return :done   if choice == 'no'
  end


  # --- Step: Done ------------
  def step_done
    printf "\n\n"
    printf "Goodbye!\n\n"
    Kernel::exit()
  end




  # ============ Prompts ============ #



  # --- Prompt: Mode ------------
  def prompt_mode
    mode = prompt("Are you configuring for QA or Production?", ['qa', 'production'], 'qa')

    # Just to be clear.
    return :QA          if mode == "qa"
    return :PRODUCTION  if mode == "production"
  end


  # --- Prompt: Model ------------
  def prompt_model
    #TODO: auto determine this from the api responses

    # This text uses "type" instead of "model" since the referenced label makes it confusing.
    printf "Which type of printer are you configuring?\n"
    printf "This number begins with TM-T88__ and is printed on the label on the\n"
    printf "right side of the printer, immediately beside \"EPSON\".\n"
    printf "  ex: EPSON TM-T88VI\n"
    printf "      answer: vi\n"
    printf "\n\n"

    type = prompt "Printer type?", ['v', 'vi'], 'vi'

    return "T88V"   if type == 'v'
    return "T88VI"  if type == 'vi'
  end


  # --- Prompt: IP ------------
  def prompt_ip
    printf "What's the IP of the printer are you configuring?\n"
    printf "You can find it on the initial printout. It looks like this:\n"
    printf "    IP: x.x.x.x\n"
    printf "\n"

    while true  # meh
      ip = prompt("Printer's IP:")
      return ip  if valid_ip?(ip)

      printf "Invalid IP.\n\n"
    end
  end


  # --- Prompt: Merchant ------------
  def prompt_merchant
    printf "Please enter the Merchant's ID from Admin Tools.\n"

    while true  # meh
      id = prompt("Merchant ID:")
      return id  if valid_merchant_id?(id)

      printf "Invalid Merchant ID.\n\n"
    end
  end


  # --- Prompt: Password ------------
  def prompt_password
    prompt("If the printer has a custom password, enter it here:", nil, 'epson')
  end




  # ============ Validation ============ #



  # --- (User) Validation: Merchant data ------------
  def verify_merchant(mode, id)
    url  = admt_api_url(mode, :validate)

    json = JSON.parse RestClient.post(url, {
      data: {
        token: @TOKEN[mode],
        merchant_id: id
      }
    })

    # Failure response
    if json['status'] == 0
      printf "\n\n"
      printf json['data']
      printf "\n\n"
      printf "The merchant is either not set up for Epson yet,\n"
      printf "or already has an associated printer.\n"
      printf "Try another merchant!"
      printf "\n\n\n"

      return false
    end

    # Success!  Display merchant info
    printf "\n\n"
    printf "Selected merchant:"
    printf "\n  ID:       " + json['data']['id'].to_s
    printf "\n  Name:     " + json['data']['merchant_name'].to_s
    printf "\n  Location: " + json['data']['location'].to_s
    printf "\n\n"

    printf "This is a "
    printf (json['data']['valid'] == false ? "in" : "")
    printf "valid merchant!\n\n\n"
    return true

  rescue RestClient::Exception => e
    printf "\n"
    printf "An error occured:  " + e.message
    printf "\n\n\n"
    return false
  end


  # --- Validation: Merchant ID ------------
  def valid_merchant_id?(id)
    # Only handles strings
    return false  if id.nil?
    return false  if (id =~ /^[0-9]+$/).nil?  # Contains non-digits
    return false  if id.to_i == 0
    true
  end


  # --- Validation: IP ------------
  def valid_ip?(ip)
    # Presence
    return false  if     ip.nil?
    return false  if     ip.empty?
    return false  unless ip.is_a? String  # being anal =p

    # Octet count
    octets = ip.split(".")
    return false  if ip.count('.') != 3  # catches a trailing '.'
    return false  if octets.count  != 4

    # Octet range
    return false  unless (1..254).include?(octets[0].to_i)
    return false  unless (0..255).include?(octets[1].to_i)
    return false  unless (0..255).include?(octets[2].to_i)
    return false  unless (1..254).include?(octets[3].to_i)

    true
  end



  # ============ Printer Configuration ============ #


  # Took enough to get here, eh?
  def autoconfigure(mode, id, ip, password)
    config = get_merchant_info(mode, id)  # Fetch the printer config from the server.

    if config.nil?
      printf "\n\n"
      printf "Could not fetch the printer config from the server.\n\n"
      return
    end

    printf "Autoconfiguring!\n"
    printer = Epson.new(@model, ip, password)

    # Set up the data
    printer.set_sdp           config[:sdp_url],    config[:sdp_interval]
    printer.set_status        config[:status_url], config[:status_interval], config[:id], config[:printer_name]
    printer.set_password      config[:password]
    printer.set_administrator config[:administrator], config[:location]
    # and send it to the printer!
    printer.apply!

    printf "Done!\n"
    printf "\n"

    # send_test_redemption(mode, id)

  rescue => e
    printf "Something went wrong :(\n"
    printf "details:\n"
    pp e
    pp e.message
    printf "\n\n"
  end




  # ============ API ============ #



  def admt_api_url(mode, endpoint)
    unless [:config, :validate, :test].include? endpoint
      raise ArgumentError, "Invalid endpoint #{endpoint} passed to admt_api_url()"
    end

    url  = "https://"
    url += "qa"                    if mode == :QA
    url += "admin.itson.me/admt/envs/"

    url += "config_epson"          if endpoint == :config
    url += "validate_merchant"     if endpoint == :validate
    url += "send_test"             if endpoint == :test

    url += "?format=json"
    url
  end



  def get_merchant_info(mode, id)
    url  = admt_api_url(mode, :config)

    response = RestClient.post(url, {
      data: {
        token: TOKEN[mode],
        merchant_id: id
      }
    })

    json = JSON.parse(response)

    # Failure response
    if json["status"] == 0
      printf "\n\n"
      printf "Something went wrong.\n"
      printf "Here's the details:\n"
      pp json
      printf "\n\n"

      return nil
    end

    # Success!
    data = {
      id:              json['data']['id'],               # @client.application_key,
      password:        json['data']['password'],         # @client.password,
      administrator:   json['data']['administrator'],    # SERVICE_NAME,
      location:        json['data']['location'],         # @client.location_slug,
      printer_name:    json['data']['printer_name'],     # @client.url_name,
      sdp_url:         json['data']['sdp_url'],          # "https://#{qa}printer.itson.me/events/callbacks/epson_check",
      sdp_interval:    json['data']['sdp_interval'],     # 15,
      status_url:      json['data']['status_url'],       # "https://#{qa}printer.itson.me/events/callbacks/epson_status",
      status_interval: json['data']['status_interval'],  # 240,
      merchant_name:   json['data']['merchant_name']     # @client_partner_name
    }

    # May as well display this.
    printf "\n\n"
    printf "Recieved the configuration from the server:\n\n"
    pp data
    printf "\n\n"

    return data


  rescue RestClient::Exception => e
    printf "\n\n"
    printf "Something went wrong.\n"
    printf "Here's the details:\n"
    pp e.message
    printf "\n\n"

    return nil
  end
end


# Alright, let's run this thing!
# Menu.new.start





# For debugging

def start
  Menu.new.start
end


$printer = Epson.new(:T88VI, "10.0.0.95")
# $printer.set_password 'epson'
$printer.set_sdp      "http://test-sdp.itson.me",     60, "cl_test_id", "autoconfigure_qa_printer"
# $printer.set_status   "http://test-status.itson.me", 240, "cl_test_id", "autoconfigure_qa_printer"

