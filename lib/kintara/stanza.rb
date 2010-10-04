#
# kintara: malkier xmpp server
# lib/kintara/stanza.rb: process XMPP stanzas
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
#%w().each { |m| require m }

# Import required application modules
%w(xml).each { |m| require 'kintara/' + m }

module XMPP

module StanzaProcessor

    extend self

    # Makes sure an XID isn't gibberish
    def verify_xid(xid)
    end

    # All of this logic comes from RFC Section 11
    # This is long and nasty, but efficient and appropriate
    def process_stanza(stanza)
        #debug("processing: #{stanza}") 

        s_type = stanza.name
        s_to   = stanza.attributes['to']

        if s_to and not s_to.empty?
            s_node, s_domain, s_resource = XML.split_xid(s_to)
        end

        # Features valid only when not fully connected
        case s_type
        when 'starttls'
            start_tls(stanza)
            return
        end unless @state.include?(:tls) and @state.include?(:sasl)

        # Is the stanza sent in the correct context?
        # (ready for iq, presence, etc etc)

        # Section 11.1 - no 'to' address
        #     Server MUST handle directly.
        if not s_to or s_to.empty?
            case s_type
            when 'message' # Section 11.1.2
                # Add 'to' attribute as bare JID of sender

            when 'presence' # Section 11.1.3
                # Deliver to sending entity's subscribers

            when 'iq' # Section 11.1.4
                # Handle on behalf of sender

            else
                error('unsupported-stanza-type')
                return
            end

        # Section 11.2 - 'to' domain is local
        elsif Kintara.config[:domains].include?(s_domain)
            # Section 11.2.1 - mere domain
            if not s_node and not s_resource
                # Sent directly to our server
                # Opening streams don't get here, so it's almost always an iq.

            # Section 11.2.2 - domain with resource
            elsif s_resource and not s_node
                # Handle as appropriate depending on type

            # Section 11.2.3 - node at domain
            elsif s_node and not s_resource
                # Section 11.2.3.1 - no such user

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
