#
# kintara: malkier xmpp server
# lib/kintara/iq.rb: processes iq stanzas
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
#%w().each { |m| require m }

# Import required application modules
#%w().each { |m| require m }

module XMPP

# Used *only* as a mixin to XMPP::Client
# Separated for brievity
module IQProcessor

    extend self

    def process_iq(stanza)
        iq_type = stanza.attributes['type']

        if iq_type == 'set'
            set_iq(stanza)
        elsif iq_type == 'get'
            get_iq(stanza)
        else
            stanza_error(stanza, 'bad-request', :modify)
        end
    end

    def set_iq(stanza)
        stanza.elements.each do |elem|
            case elem.name
            when 'bind'
                bind_resource(stanza)
            when 'unbind'
                stanza_error(stanza, 'feature-not-implemented', :modify)
            when 'session'
                fake_session(stanza)
            else
                stanza_error(stanza, 'service-unavailable', :cancel)
            end
        end
    end

    def get_iq(stanza)
        stanza.elements.each do |elem|
            case elem.name
            when 'XXX'
            else
                stanza_error(stanza, 'service-unavailable', :cancel)
            end
        end
    end

    def bind_resource(stanza)
        elem = stanza.elements.find { |e| e.name == 'bind' }

        # Verify the namespace
        unless elem.namespace == XML::NS::BIND
            stanza_error(stanza, 'service-unavailable', :cancel)
            return
        end

        # How many do they have bound now?
        if @user.resources.length > 10
            stanza_error(stanza, 'resource-constraint', :cancel)
            return
        end

        # Abort if this Client already has one bound
        if @resource
            stanza_error(stanza, 'not-allowed', :cancel)
            return
        end

        # If they don't give us a <resource> we make it up for them
        if elem.has_elements?
            name = elem.elements['resource'].text[0 ... 1024]
            @resource = XMPP::Resource.new("#{name}#{SecureRandom.hex(3)}")
        else
            @resource = XMPP::Resource.new(XML.uuid)
        end

        @resource.client = self
        @user.resources << @resource

        @state << :bind

        log(:debug, "bound resource to #{@resource.name}")

        # Yay they now have a resource
        result = XML.new_iq(:result, stanza.attributes['id'])
        bind   = XML.new_element('bind', XML::NS::BIND)

        jid = XML.new_element('jid')
        jid.text = "#{@user.xid}/#{@resource.name}"

        bind   << jid
        result << bind

        @sendq << result

        send_features
    end

    ##
    # Session has been removed in the latest draft RFC.
    # I'm keeping this here because none of the clients
    # I tested actually bother to look for it in <features/>
    # and just send the iq stanza anyway.
    #
    # This just returns the stanza with success. Nothing happens.
    #
    def fake_session(stanza)
        @sendq << XML.new_iq(:result, stanza.attributes['id'])

        send_features
    end

end # module IQProcessor

end # module XMPP

