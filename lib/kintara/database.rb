#
# kintara: malkier xmpp server
# lib/kintara/database.rb: data structure storing
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#

module DB

    class User < Sequel::Model
        one_to_many :roster_entries
        one_to_many :offline_stanzas

        def User.find_xid(xid)
            node, domain, resource = XML.split_xid(xid)
            User.find(:node => node, :domain => domain)
        end

        def xid
            "#{node}@#{domain}"
        end

        ##
        # This is stuff that doesn't have to do with the database
        #

        # A list of XMPP::Clients connected as us
        def clients
            @clients ||= []
            @clients
        end

        # A list of XMPP::Resources bound under our @clients
        def resources
            @resources ||= []
            @resources
        end
    end

    class RosterEntry < Sequel::Model
        one_to_many :groups
        many_to_one :user
    end

    class OfflineStanza < Sequel::Model
        many_to_one :user
    end

    class Group < Sequel::Model
        many_to_one :roster_entries
    end

    # Sets up a new skeleton DB
    # XXX - should probably do this stuff with migrations and rake
    def DB.initialize
        Kintara.db.create_table :users do
            primary_key :id
            String      :node
            String      :password
            String      :domain
            String      :vcard
        end

        Kintara.db.create_table :roster_entries do
            primary_key :id
            foreign_key :user_id, :users
            String      :remote_xid
            String      :alias
            String      :subscription
            FalseClass  :ask
        end

        Kintara.db.create_table :offline_stanzas do
            primary_key :id
            foreign_key :user_id, :users
            String      :stanza
            Time        :timestamp
        end

        Kintara.db.create_table :groups do
            primary_key :id
            foreign_key :roster_entry_id, :roster_entries

            String :name
        end
    end

end # module DB
