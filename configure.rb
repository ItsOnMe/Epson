# Epson printer automatic configuration!

# Caveats:
#  * cannot set blank values on the printer


require 'pp'
require 'colorize'
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

    while true
      clear_screen
      display_menu

      step = case(step)
      when :mode
        step_mode
      when :confirm_mode
        step_mode_confirm
      when :merchant
        step_merchant
      when :model
        step_model
      when :ip
        step_ip
      when :autoconfigure
        step_autoconfigure
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
      mode_string = mode_string.green  if @mode == :QA
      mode_string = mode_string.red    if @mode == :PRODUCTION
    end

    # Display header
    header  = ""
    header += " ☼ ".cyan.on_blue
    header += " ItsOnMe".light_blue
    header += "  --  "
    header += "Epson Printer Configuration"
    header += "#{mode_string}\n"
    header += (("-"*70) + "\n").light_black

    printf header

    # " ☼ ItsOnMe  --  Epson Printer Configuration #{mode_string}\n"
    # "----------------------------------------------------------------------\n"

    # Display printer info, if present.
    printer_info = []
    printer_info << "Model #{@model}"  if @model.present?
    printer_info << "IP: #{@ip}"       if @ip.present?
    printf printer_info.join(", ").cyan

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

    :merchant
  end


  # --- Step: Model ------------
  def step_model
    @model = prompt_model
    :ip
  end


  # --- Step: IP ------------
  def step_ip
    @ip = prompt_ip
    :autoconfigure
  end


  # --- Step: Merchant ------------
  def step_merchant
    valid = false
    until valid
      merchant_id = prompt_merchant
      valid = verify_merchant(@mode, merchant_id)
    end

    choice = prompt("Is this correct?", ['y', 'n'])

    # Incorrect? repeat this step.
    return :merchant  if choice == 'no'


    @merchant_id = merchant_id
    :model
  end


  # --- Step: Autoconfigure ------------
  def step_autoconfigure
    printf "Alright, let's configure the printer!\n\n"

    autoconfigure(@mode, @merchant_id, @model, @ip)

    # Cleanup
    @model = @ip = @merchant_id = nil

    printf "\n\n"
    choice = prompt("Configure another?", ['yes', 'no'], 'yes')
    return :merchant  if choice == 'yes'


    # --- Done! ------

    printf "\n\n"
    printf "Goodbye!\n\n".cyan
    Kernel::exit()
  end



  # ============ Prompts ============ #



  # --- Prompt: Mode ------------
  def prompt_mode
    mode = prompt("Are you configuring for QA or Production?", ['qa', 'production'], 'production')

    # Just to be clear.
    return :QA          if mode == "qa"
    return :PRODUCTION  if mode == "production"
  end


  # --- Prompt: Model ------------
  def prompt_model
    #TODO: auto determine this from the api responses

    # This text uses "type" instead of "model" since the referenced label makes it confusing.
    printf "Which type of printer are you configuring?\n"
    printf "This number begins with TM-T88__ and is printed on the label on the\n".light_black
    printf "right side of the printer, immediately beside \"EPSON\".\n".light_black
    printf "  ex: EPSON TM-T88VI\n".light_black
    printf "      answer: vi\n".light_black
    printf "\n\n"

    type = prompt "Printer type?", ['v', 'vi'], 'vi'

    return "T88V"   if type == 'v'
    return "T88VI"  if type == 'vi'
  end


  # --- Prompt: IP ------------
  def prompt_ip
    printf "What's the IP of the printer are you configuring?\n"
    printf "You can find it on the initial printout.\n".light_black
    printf "It looks like this:\n".light_black
    printf "    IP: x.x.x.x\n".light_black
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
  def prompt_configure_password(ip, password)
    printf "First, log into the printer.\n"
    printf "Open your browser and go here:\n".light_black
    printf "    " + "http://#{ip}\n".light_blue.underline
    printf "Here are the login credentials:\n".light_black
    printf "    username: ".light_black + "epson\n"
    printf "    password: ".light_black + "epson\n"
    printf "\n"
    printf "After logging in, click the " + "[Password]".light_blue + " link at the very bottom of the sidebar.\n"
    printf "Here are the details:\n".light_black
    printf "    old password: ".light_black + "epson\n"
    printf "    new password: ".light_black + "#{password}\n"
    printf "\n"
    printf "\n"
    printf "------------\n"

    prompt("Press enter when you're finished! ")
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
      printf json['data'].red
      printf "\n\n"
      printf "The merchant is either not set up for Epson yet,\n".red
      printf "or already has an associated printer.\n".red
      printf "\n"
      printf "Try another merchant!".light_red
      printf "\n\n\n"

      return false
    end

    # Success!  Display merchant info
    printf "\n\n"
    printf "Selected merchant ".cyan + "#{json['data']['id']}" + ":".cyan
    printf "\n  Name:     ".cyan + json['data']['merchant_name'].to_s
    printf "\n  Location: ".cyan + json['data']['location'].to_s
    printf "\n\n\n"

    return true

  rescue RestClient::Exception => e
    printf "\n"
    printf ("An error occured:  " + e.message).red
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
  def autoconfigure(mode, id, model, ip)
    config = get_merchant_info(mode, id)  # Fetch the printer config from the server.

    if config.nil?
      printf "\n\n"
      printf ("Could not fetch the printer config from the server.\n\n").red
      return
    end

    password = config[:password]
    printer  = Epson.new(model, ip, password)


    # Loop until the user has completed their task successfully
    success = false
    until success
      # Tell the user to configure the printer's password
      prompt_configure_password(ip, password)

      # Display menu again
      clear_screen
      display_menu

      printf "Testing printer connection..."
      success = printer.test_connection
      printf "\n"

      unless success
        # Display error message
        printf "Error: Unable to connect to the printer.\n".red
        printf "       Please set the password again!\n".red
        printf "\n\n"
      end
    end


    clear_screen
    display_menu
    printf "Autoconfiguring!\n"

    # Set up the data
    printf " | Server Direct Print...\n"
    printer.set_sdp           active: true, url: config[:sdp_url],    interval: config[:sdp_interval],    id: config[:id], name: config[:printer_name]
    sleep 0.125

    printf " | Status Notification...\n"
    printer.set_status        active: true, url: config[:status_url], interval: config[:status_interval], id: config[:id], name: config[:printer_name]
    sleep 0.125

    printf " | Administrator...\n"
    printer.set_administrator admin: config[:administrator], location: config[:location]
    sleep 0.125

    # printf " | Password...\n"
    # printer.set_password       password: config[:password]
    # sleep 0.125

    # and send it to the printer!
    printf " | Applying settings...\n"
    printer.apply!

    printf "Done!\n"
    printf "\n"




    # send_test_redemption(mode, id)

  rescue => e
    printf "Something went wrong :(\n".red
    printf "details:\n".red
    pp e
    pp e.message
    printf "\n\n"
  end




  # ============ API ============ #



  def admt_api_url(mode, endpoint)
    unless [:config, :validate, :test].include? endpoint
      raise ArgumentError, "Invalid endpoint #{endpoint} passed to admt_api_url()"
    end

    qa = (mode==:QA ? "qa" : "")

    api = ""
    api = "config_epson"       if endpoint == :config
    api = "validate_merchant"  if endpoint == :validate
    api = "send_test"          if endpoint == :test

    "https://#{qa}admin.itson.me/admt/envs/#{api}?format=json"
  end



  def get_merchant_info(mode, id)
    printf "Fetching configuration from the server..."

    url  = admt_api_url(mode, :config)

    response = RestClient.post(url, {
      data: {
        token: @TOKEN[mode],
        merchant_id: id
      }
    })

    json = JSON.parse(response)

    # Failure response
    if json["status"] == 0
      printf "\n\n"
      printf "Something went wrong.\n".red
      printf "Here's the details:\n".red
      pp json
      printf "\n\n"

      return nil
    end

    # Success!
    data = {
      id:              json['data']['id'],
      password:        json['data']['password'],
      administrator:   json['data']['administrator'],
      location:        json['data']['location'],
      printer_name:    json['data']['printer_name'],
      sdp_url:         json['data']['sdp_url'],
      sdp_interval:    json['data']['sdp_interval'],
      status_url:      json['data']['status_url'],
      status_interval: json['data']['status_interval'],
      merchant_name:   json['data']['merchant_name'],
    }

    # May as well display this.
    printf "\n"
    printf "Done!\n\n"
    pp data
    printf "\n\n"

    return data


  rescue RestClient::Exception => e
    printf "\n\n"
    printf "Something went wrong.\n".red
    printf "Here's the details:\n".red
    pp e.message
    printf "\n\n"

    return nil
  end
end


# Alright, let's run this thing!
Menu.new.start





__END__

# For debugging

def start
  Menu.new.start
end



$printervi = Epson.new(:T88VI, "10.0.0.95")
# $printer.set_password 'epson'
$printervi.set_sdp      "http://test-sdp.itson.me",     60, "cl_test_id--6", "autoconfigure_qa_printer--6"
# $printer.set_status   "http://test-status.itson.me", 240, "cl_test_id--6", "autoconfigure_qa_printer--6"



$printerv = Epson.new(:T88VI, "10.0.0.91")
# $printer.set_password 'epson'
$printerv.set_sdp      "http://test-sdp.itson.me",     60, "cl_test_id-5", "autoconfigure_qa_printer--5"
# $printer.set_status   "http://test-status.itson.me", 240, "cl_test_id--5", "autoconfigure_qa_printer--5"
