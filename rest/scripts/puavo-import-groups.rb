#!/usr/bin/ruby

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

options = cmd_options(:message => "Import groups to Puavo")

setup_connection(options)

groups = []

CSV.foreach(options[:csv_file], :encoding => options[:encoding], :col_sep => ";") do |row|
  group_data = encode_text(row, options[:encoding])

  next if !options[:include_schools].nil? && !options[:include_schools].include?(group_data[2].to_s)

  group = PuavoImport::Group.new(
    :external_id => group_data[0],
    :name => group_data[1],
    :school_external_id => group_data[2]
  )

  if group.school
    groups.push(group)
  else
    STDERR.puts "Puts cannot find school for data: #{ group_data.inspect }"
  end

end

case options[:mode]
when "diff"
  puts "Compare current group data for import data\n\n"

  groups.each do |group|
    puavo_group = PuavoRest::Group.by_attr(:external_id, group.external_id)

    unless puavo_group
      puts brown("Add new group: #{ group.to_s }")
      next
    end

    if !group.need_update?(puavo_group) && options[:silent]
      next
    end

    diff_objects(puavo_group, group, ["name", "external_id", "abbreviation"])

    puts "\n" + "-" * 100 + "\n\n"
  end
when "set-external-id"

  puts "Set external id\n\n"

  @sticky_response = nil
  groups.each do |group|

    puavo_group = PuavoRest::Group.by_attr(:external_id, group.external_id)

    if puavo_group.nil?
      puavo_group = PuavoRest::Group.by_attrs(
        :name => group.name,
        :school_dn => group.school.dn
      )
    end

    if puavo_group.nil?
      puts "Can not find group from Puavo: #{ group.name }\n\n"
      next
    end

    diff_objects(puavo_group, group, ["name", "external_id", "abbreviation"])

    if puavo_group.external_id != group.external_id
      if @sticky_response.nil?
        response = ask("Update external_id (#{ group.external_id }) to Puavo (Y/N)?",
                       :default => "N")
      end

      @sticky_response = "!" if response == "!"
      if response == "Y" || @sticky_response == "!"
        puts "Update external id"
        puavo_group.external_id = group.external_id
        puavo_group.save!
      end
    end

    puts "\n" + "-" * 100 + "\n\n"
  end
when "import"
  puts "Import groups\n\n"
  groups.each do |group|
    puavo_rest_group = PuavoRest::Group.by_attr(:external_id, group.external_id)
    if puavo_rest_group
      if group.need_update?(puavo_rest_group)
        puts "#{ group.to_s }: update group information"
        puavo_rest_group.name = group.name
        puavo_rest_group.abbreviation = group.abbreviation
        puavo_rest_group.school_dn = group.school.dn
        puavo_rest_group.save!
      else
        next if options[:silent]
        puts "#{ group.to_s }: no changes"
      end
    else
      puts "#{ group.to_s }: add group to Puavo"
      PuavoRest::Group.new(:name => group.name,
                           :external_id => group.external_id,
                           :abbreviation => group.abbreviation,
                           :type => "teaching group",
                           :school_dn => group.school.dn).save!
    end
  end
end
