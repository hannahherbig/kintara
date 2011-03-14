#
# kintara: malkier xmpp server
# lib/kintara/stanza.rb: process XMPP stanzas
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
#%w().each { |m| require m }

# Import required application modules
%w(xml).each { |m| require 'kintara/' + m }

module XMPP

# Used *only* as a mixin to XMPP::Client
# Separated for brievity
module StanzaProcessor

    extend self

    # Makes sure an XID isn't gibberish
    def verify_xid(xid)
    end

    # All of this logic comes from RFC Section 11
    # This is long and nasty, but efficient and appropriate
    def process_stanza(stanza)
        s_type = stanza.name
        s_to   = stanza.attributes['to']

        # Doing this here makes the flow control prettier
        node, domain, resource = XML.split_xid(s_to)

        # Features valid only when not fully connected
        case s_type
        when 'starttls'
            start_tls(stanza)
            return
        when 'auth'
            authorize(stanza)
            return
        end unless @state.include?(:tls) and @state.include?(:sasl)

        # Is the stanza sent in the correct context?
        # (ready for iq, presence, etc etc)

        # Section 11.1 - no 'to' address
        #     Server MUST handle directly.
        if not s_to or s_to.empty?
            case s_type
            when 'message'
                # Add 'to' attribute as bare JID of sender

            when 'presence'
                # Deliver to sending entity's subscribers

            when 'iq'
                # Treated the same as "to: mere domain"
                @eventq.post(:iq_stanza_ready, stanza)

            else
                stream_error('unsupported-stanza-type')
            end

        # Section 11.2 - 'to' domain is local
        elsif Kintara.config[:domains].include?(domain)
            # Section 11.2.1 - mere domain
            if not node and not resource
                if s_type == 'iq'
                    @eventq.post(:iq_stanza_ready, stanza)
                else
                    stanza_error(stanza, 'bad-request', :modify)
                end

            # Section 11.2.2 - domain with resource
            elsif resource and not node
                # I don't know what this could apply to currently
                stanza_error(stanza, 'bad-request', :modify)

            # Section 11.2.3 - node at domain
            elsif node and not resource
                # Section 11.2.3.1 - no such user
                if not DB::User.find_xid(s_to) and s_type =~ /(message|iq)/
                    stanza_error('service-unavailable', :cancel)
                end

                # Section 11.2.3.2 - depends on stanza type
                case s_type
                when 'message'
                    # Deliver to at least one resource, or store offline

                when 'presence'
                    # Deliver to at least one resource, or silently ignore

                when 'iq'
                    # Handle directly on behalf of recepient
                end
            end

        # Section 11.3 - foreign domain
        else
            # Route away!
        end
    end

end # module XML

end # module XMPP
