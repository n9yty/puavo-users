#!/usr/bin/ruby1.9.3
# -*- coding: utf-8 -*-

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

options = PuavoImport.cmd_options

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

CSV.foreach(options[:csv_file], :encoding => options[:encoding] ) do |row|
  group_data = PuavoImport.csv_row_to_array(row, options[:encoding])
  PuavoImport::Group.new(:external_id => group_data[0],
                         :name => group_data[1],
                         :school_external_id => group_data[2])
end

mode = "default"

mode = "import" if options[:import]

case mode
when "import"
  puts "Import groups\n\n"
  PuavoImport::Group.all.each do |group|
    puavo_rest_group = PuavoRest::Group.by_attr(:external_id, group.external_id)
    if puavo_rest_group
      if puavo_rest_group.name != group.name
        puts "#{ group.to_s }: update name"
        puavo_rest_group.name = group.name
        puavo_rest_group.save!
      else
        puts "#{ group.to_s }: no changes"
      end
    else
      puts "#{ group.to_s }: add group to Puavo"
      abbreviation = group.name.downcase
      abbreviation.gsub!(/[åäö ]/, "å" => "a", "ä" => "a", "ö" => "o", " " => "-")
      abbreviation.gsub!(/[ÅÄÖ]/, "Å" => "a", "Ä" => "a", "Ö" => "o")
      abbreviation.gsub!(/[^a-z0-9-]/, "")
      abbreviation = group.school.abbreviation.slice(0..3) + "-opp-" + abbreviation
      PuavoRest::Group.new(:name => group.name,
                           :external_id => group.external_id,
                           :abbreviation => abbreviation,
                           :school_dn => group.school.dn).save!
    end
  end
end