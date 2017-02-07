require 'uservoice-ruby'

SUBDOMAIN_NAME = ENV['USERVOICE_SUBDOMAIN_NAME'].freeze
API_KEY = ENV['USERVOICE_API_KEY'].freeze
API_SECRET = ENV['USERVOICE_API_SECRET'].freeze

client = UserVoice::Client.new(SUBDOMAIN_NAME, API_KEY, API_SECRET)
client.login_as_owner do |owner|
  user = owner.get('/api/v1/users/current')['user']
  puts user
end
