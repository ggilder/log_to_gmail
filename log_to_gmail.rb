#!/usr/bin/env ruby

Dir.chdir(File.dirname(File.expand_path(__FILE__)))

require 'rubygems'
require 'bundler'

Bundler.require

require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'action_view'
require 'fileutils'
require 'open3'

include ActionView::Helpers::DateHelper

# Process arguments
command = ARGV
if command.count == 0
  $stderr.puts "Missing command to run!"
  exit 1
end

# Config
# TODO: make this more configurable
task_label = command.join(' ')
label = "LogToGmail"
subject_text = "Task Completed"
subject = "[#{label}] #{subject_text}"
config_path = File.join(Dir.home, '.log_to_gmail').freeze

class GmailWrapper
  OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'.freeze
  APPLICATION_NAME = 'Log To Gmail'.freeze
  SCOPE = [Google::Apis::GmailV1::AUTH_GMAIL_SEND, Google::Apis::GmailV1::AUTH_GMAIL_READONLY]

  attr_reader :config_path, :credentials_path, :token_path

  def initialize(config_path)
    @config_path = config_path
    @credentials_path = File.join(config_path, 'credentials.json')
    # The file token.yaml stores the user's access and refresh tokens, and is
    # created automatically when the authorization flow completes for the first
    # time.
    @token_path = File.join(config_path, 'token.yaml')
  end

  def service
    @service ||= load_service
  end

  def load_service
    service = Google::Apis::GmailV1::GmailService.new
    service.client_options.application_name = APPLICATION_NAME
    service.authorization = authorize
    service
  end

  # Ensure valid credentials, either by restoring from the saved credentials
  # files or intitiating an OAuth2 authorization. If authorization is required,
  # the user's default browser will be launched to approve the request.
  def authorize
    client_id = Google::Auth::ClientId.from_file(credentials_path)
    token_store = Google::Auth::Stores::FileTokenStore.new(file: token_path)
    authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)
    user_id = 'default'
    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(base_url: OOB_URI)
      puts 'Open the following URL in the browser and enter the ' \
        "resulting code after authorization:\n" + url
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id, code: code, base_url: OOB_URI
      )
    end
    credentials
  end

  def user_email_address
    @user_email_address ||= service.get_user_profile('me').email_address
  end

  def send_self_message(subject, body)
    message = Mail.new(
      to: user_email_address,
      from: user_email_address,
      subject: subject,
      body: body
    )
    message_object = Google::Apis::GmailV1::Message.new(raw: message.to_s)
    service.send_user_message('me', message_object)
  end
end

gmail = GmailWrapper.new(config_path)
# Make sure we can authorize before running script
gmail.service

puts "Running task `#{task_label}`"
start_time = Time.now
out, status = Open3.capture2e(*command)
stop_time = Time.now
elapsed = distance_of_time_in_words(start_time, stop_time)

body = <<EOD
Task: #{task_label}
Start Time: #{start_time}
Stop Time: #{stop_time} (#{elapsed})
Status: #{status.exitstatus}
Standard output/error:
#{out}

---

Have a nice day!
EOD

gmail.send_self_message(subject, body)
puts "Completed task in #{elapsed}"
puts "Exit status: #{status.exitstatus}"
puts "Lines of output: #{out.lines.count}"
puts "Sent email with log"
