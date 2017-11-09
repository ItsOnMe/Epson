# Epson printer autoconfiguration

**Fair warning:** This is still non-functional for model T88VI printers. I'm waiting to hear back from Epson on why that printer model's API isn't working as documented.

### Setup:
  - Install Ruby v2.3.4
  - run `gem install bundler`
  - run `bundle install`

### Usage:
  - Run `ruby ./configure.rb` and follow the prompts.


------


### Debugging Usage:

  - Loading the script: `irb -r ./configure.rb`
  - Starting the menu:  `start`
  - Printer configuration test:  `$printervi.apply!`
  - Printer configuration test:  `$printerv.apply!`

(`$printer*` are  Epson objects pre-loaded with test configuration data.  The IPs are hardcoded to `10.0.0.95` and `.91`)
