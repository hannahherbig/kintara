#
# kintara: malkier xmpp server
# lib/kintara/database.rb: data structure storing
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
#%w().each { |m| require m }

# Import required application modules
#%w().each { |m| require m }

# Check for Sequel
begin
    require 'sequel'
rescue LoadError
    puts 'kintara: unable to load Sequel'
    puts 'kintara: this library is required for database storage'
    puts 'kintara: gem install --remote sequel'
    abort
end

