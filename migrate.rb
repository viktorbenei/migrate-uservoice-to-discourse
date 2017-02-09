require 'uservoice-ruby'
require 'discourse_api'

@configs = {
  uservoice: {
    SUBDOMAIN_NAME: ENV['USERVOICE_SUBDOMAIN_NAME'].chomp('/'),
    API_KEY: ENV['USERVOICE_API_KEY'],
    API_SECRET: ENV['USERVOICE_API_SECRET'],
    MIN_VOTE_COUNT_TO_MIGRATE: ENV['USERVOICE_MIN_VOTE_COUNT_TO_MIGRATE'].to_i,
    # specify this in case you have more than one forums
    forum_id: ENV['USERVOICE_FORUM_ID']
  },
  discourse: {
    DOMAIN: ENV['DISCOURSE_DOMAIN'],
    USERNAME: ENV['DISCOURSE_USERNAME'],
    API_KEY: ENV['DISCOURSE_API_KEY'],
    CATEGORY_TO_MIGRATE_INTO: ENV['DISCOURSE_CATEGORY_TO_MIGRATE_INTO']
  }
}

puts '----------'
puts "Configs: #{@configs}"
puts '----------'

#
class DiscourseCommunicator
  def initialize(domain, username, api_key, category_to_migrate_into)
    @domain = domain.chomp('/')
    @client = DiscourseApi::Client.new(domain)
    @client.api_username = username
    @client.api_key = api_key
    @category_to_migrate_into = category_to_migrate_into
  end

  # source/based on:
  # https://github.com/discourse/github-issues-to-discourse/blob/master/lib/discourseCreateTopic/index.js
  def discourse_create_topic(uv_feature_req)
    # Create Topic at Discourse Instance
    freq_date = uv_feature_req['created_at']
    freq_body = !uv_feature_req['text'].to_s.empty? ? uv_feature_req['text'] : "_(empty description)_"

    topic_body = "<i>From " + uv_feature_req['creator']['name'] + " on " + freq_date + "</i><br /><br />" + freq_body + "<br /><br />" + "<i>Copied from original feature request: " + uv_feature_req['url'] + "</i>"

    # source: https://github.com/discourse/discourse_api/blob/master/examples/create_topic.rb
    @client.create_topic(
      category: @category_to_migrate_into,
      title: uv_feature_req['title'],
      raw: topic_body,

      skip_validations: true,
      auto_track: false
    )
  end

  # source/based on:
  # https://github.com/discourse/github-issues-to-discourse/blob/2cdaed0c546c319cc2b4f6ffb8c33ba6556d28a1/routes/api/discourse.js#L63
  def discourse_topic_url(topic_api_obj)
    return "#{@domain}/t/#{topic_api_obj['topic_slug']}/#{topic_api_obj['topic_id']}"
  end

  def discourse_reply_to_topic(discourse_topic_id, uv_comment)
    comment_date = uv_comment['created_at']
    comment_body = "<i>From " + uv_comment['creator']['name'] + " on " + comment_date + "</i><br /><br />" + uv_comment['text']

    @client.create_post(
      topic_id: discourse_topic_id,
      raw: comment_body
    )
  end
end

dc_configs = @configs[:discourse]
dc_communicator = DiscourseCommunicator.new(
  dc_configs[:DOMAIN],
  dc_configs[:USERNAME],
  dc_configs[:API_KEY],
  dc_configs[:CATEGORY_TO_MIGRATE_INTO]
)


@uv_configs = @configs[:uservoice]
@uv_client = UserVoice::Client.new(@uv_configs[:SUBDOMAIN_NAME], @uv_configs[:API_KEY], @uv_configs[:API_SECRET])

if @uv_configs[:forum_id].to_s.empty?
  forums = @uv_client.get_collection('/api/v1/forums')
  forum_cnt = 0
  forums.each do |forum|
    puts forum
    @uv_configs[:forum_id] = forum['id']
    forum_cnt += 1
  end
  if forum_cnt > 1
    raise 'More than one forum found, you have to specify the ID with USERVOICE_FORUM_ID'
  end
end
puts " (i) Using forum id: #{@uv_configs[:forum_id]}"

def uv_get_comments(suggestion_id)
  @uv_client.get_collection("/api/v1/forums/#{@uv_configs[:forum_id]}/suggestions/#{suggestion_id}/comments.json")
end

def uv_close_suggestion(suggestion_id, close_reason_text)
  url = "/api/v1/forums/#{@uv_configs[:forum_id]}/suggestions/#{suggestion_id}/respond"

  resp = @uv_client.login_as_owner do |owner|
    owner.put(url, {
      response: {
        status: 'Completed',
        text: close_reason_text
      },
      # For testing, if you don't want to notify users who voted/supported the suggestion:
      # notify: false
    })
  end
  raise "Failed to close suggestion: #{resp}" if resp['suggestion'].nil?
end

suggestions = @uv_client.get_collection("/api/v1/forums/#{@uv_configs[:forum_id]}/suggestions?sort=oldest")
suggestions_count = suggestions.size
puts " (i) Total suggestions: #{suggestions_count}"

migration_stats = {
  skipped_because_closed_count: 0,
  skipped_because_not_enough_votes_count: 0,
  migrated_count: 0
}
#
dc_domain = @configs[:discourse][:DOMAIN]
dc_feature_request_category = @configs[:discourse][:CATEGORY_TO_MIGRATE_INTO]
# Loops through all the suggestions and loads new pages as necessary.
suggestion_idx = 0
suggestions.each do |suggestion|
  suggestion_idx += 1
  puts
  puts "=> [#{suggestion_idx} / #{suggestions_count}]"
  puts

  # puts "Suggestion: #{suggestion.to_json}"

  suggestion_title = suggestion['title']
  suggestion_id = suggestion['id']

  # don't migrate closed feature requests
  if suggestion['state'] == 'closed'
    puts " (-) Ignoring suggestion because it's closed: #{suggestion_title}"
    migration_stats[:skipped_because_closed_count] += 1
    next
  end

  suggestion_votes_count = suggestion['vote_count'].to_i
  if suggestion_votes_count < @uv_configs[:MIN_VOTE_COUNT_TO_MIGRATE]
    puts " (x) Skipping creation of feature request, because the suggestion does not have enough votes (#{suggestion_votes_count}): #{suggestion_title}"
    migration_stats[:skipped_because_not_enough_votes_count] += 1

    # Close on UserVoice
    puts "     ==> Closing it on UserVoice with a note message"
    close_message = "We're migrating our feature requests to #{dc_domain}.

As this feature request did not reach the minimum vote count for auto migration, we won't auto create a feature request for it at #{dc_domain}.
If you think this feature request is still relevant, please go to #{dc_domain} and create a new feature request in the #{dc_feature_request_category} category.

Thank you everyone for supporting this feature request here!
"
    uv_close_suggestion(suggestion_id, close_message)
    next
  end

  puts
  puts " (+) Create topic: #{suggestion_title}"
  dc_topic = dc_communicator.discourse_create_topic(suggestion)
  # puts dc_topic.to_json
  dc_topic_url = dc_communicator.discourse_topic_url(dc_topic)
  puts "     Topic URL: #{dc_topic_url}"
  puts

  puts "==> Migrating comments ..."
  uv_comments = uv_get_comments(suggestion_id)
  uv_comments.each do |uv_comment|
    # puts
    # puts "* Comment: #{uv_comment.to_json}"
    # puts "==> Migrating comment: #{uv_comment['text']}"
    dc_post = dc_communicator.discourse_reply_to_topic(dc_topic['topic_id'], uv_comment)
    # puts dc_post.to_json
    # puts
  end

  # Close on UserVoice
  puts "==> Close original feature request on UserVoice ..."

  close_message = "We're migrating our feature requests to #{dc_domain}.
Thank you everyone for supporting this feature request here!

This feature request was moved to: #{dc_topic_url}
Please vote and comment on it there!

Thank you everyone!
"
    uv_close_suggestion(suggestion_id, close_message)

  puts "==> Migration of item Finished"

  migration_stats[:migrated_count] += 1
  sleep 5 # API rate limits
end

puts
puts "migration_stats: #{migration_stats}"
puts
