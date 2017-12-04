# -*- coding: utf-8 -*-
require 'jira-ruby'
require 'trello'
require 'pry'
require 'rest-client'
require 'yaml'

def populate_options
  # Read config file
  config = YAML.load_file(File.join(File.dirname(__FILE__), '/jira-trello.yaml'))

  # Configure Jira
  @jira_site = config['jira']['site']
  @jira_options = {
                   :username     => config['jira']['username'],
                   :password     => config['jira']['password'],
                   :site         => @jira_site,
                   :context_path => '',
                   :auth_type    => :basic
                  }
  @jira_filter = config['jira']['filter']
  @jira_client = JIRA::Client.new(@jira_options)

  # Configure Trello
  @trello_board_id = config['trello']['board_id']
  @trello_inbox_list_id = config['trello']['inbox_list_id']
  Trello.configure do |trello_config|
    trello_config.developer_public_key = config['trello']['public_key']
    trello_config.member_token = config['trello']['token']
  end
end

def get_jira_issues
  @jira_client.Issue.jql(@jira_filter)
end

def download_jira_attachment(url)
  FileUtils.mkdir_p('tmp/attachments')
  file = File.open("tmp/attachments/#{File.basename(url)}", 'w')
  file.binmode
  file.write RestClient::Request.execute(
                                         :method   => :get,
                                         :url      => url,
                                         :user     => @jira_options[:username],
                                         :password => @jira_options[:password]
                                        )
  file.close
  File.open(file.path)
end

def trello_board
  Trello::Board.find(@trello_board_id)
end

def trello_inbox_list
  Trello::List.find(@trello_inbox_list_id)
end

def create_trello_attachments(jira_issue, trello_card)
  jira_attachments = @jira_client.Issue.find(jira_issue.id).attachments
  jira_attachments.each do |jira_attachment|
    attachment_file = download_jira_attachment(jira_attachment.content)
    trello_card.add_attachment(attachment_file)
    File.delete(attachment_file.path)
  end
end

def create_trello_cards(jira_issues)
  puts "Create Trello Cards"
  labels = trello_board.labels
  jira_issues.each do |jira_issue|
    card_name = "#{jira_issue.key} - #{jira_issue.fields['summary']}"
    jira_issue_link = "#{@jira_site}/browse/#{jira_issue.key}"
    puts card_name
    trello_card = Trello::Card.create({
                                name: card_name,
                                list_id: @trello_inbox_list_id,
                                desc: "#{jira_issue_link}\n\n\n#{jira_issue.fields['description']}",
                                card_labels: labels.select{|l| l.name == jira_issue.fields["priority"]["name"]}.map{|l| l.id}.join(",")
                               })
    create_trello_attachments(jira_issue, trello_card)
    trello_card
  end
end

def clear_trello_inbox
  trello_inbox_list.cards.each do |card|
    card.delete
  end
end

def sync_trello_cards
  jira_issues = get_jira_issues
  jira_issue_keys = jira_issues.map{|i| i.key}
  trello_card_keys = trello_board.cards.map{|c| c.name.split(" - ")[0]}
  new_jira_keys = jira_issue_keys - trello_card_keys
  new_jira_issues = jira_issues.select{|issue| new_jira_keys.include?(issue.key)}
  puts "Found #{new_jira_issues.count} new JIRA issues"
  create_trello_cards(new_jira_issues)
  #inactive_trello_keys = trello_card_keys - jira_issue_keys
  #puts "Inactive Trello cards: #{inactive_trello_keys}"
end

def main
  populate_options
  #clear_trello_inbox
  sync_trello_cards
end

main
