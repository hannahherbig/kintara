#
# kintara: malkier xmpp server
# lib/kintara/stream.rb: stream initializers
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
module Stream

    extend self

    def stream_error(defined_condition)
        err = XML.new_element('stream:error')
        na  = XML.new_element(defined_condition,
                              'urn:ietf:params:xml:ns:xmpp-streams')
        err << na

        @sendq << err

        self.dead = true
    end

    def stanza_error(stanza, defined_condition, type)
        stzerr = XML.new_element(stanza.name)
        stzerr.add_attribute('type', 'error')
        stzerr.add_attribute('id', stanza.attributes['id'])

        err = XML.new_element('error')
        err.add_attribute('type', type.to_s)

        cond = XML.new_element(defined_condition,
                               'urn:ietf:params:xml:ns:xmpp-stanzas')

        err << cond
        stzerr << err

        @sendq << stzerr
    end

    def process_new_stream(xml)
        # Verify the namespaces
        unless xml.attributes['stream'] == 'http://etherx.jabber.org/streams'
            stream_error('invalid-namespace')
            return
        end

        unless xml.attributes['xmlns'] == 'jabber:client'
            stream_error('invalid-namespace')
            return
        end

        # Check the version
        unless xml.attributes['version'] == '1.0'
            stream_error('unsupported-version')
            return
        end

        send_stream(xml)
        send_features
    end

    def send_stream(xml)
        xmlfrom = xml.attributes['from']
        xmlto   = xml.attributes['to']
        xmlto ||= Kintara.config[:domains].first
        stanza  = []

        @connect_host = xmlto

        stanza << "<?xml version='1.0'?>"
        stanza << "<stream:stream "
        stanza << "xmlns='jabber:client' "
        stanza << "xmlns:stream='http://etherx.jabber.org/streams' "
        stanza << "xml:lang='en' "
        stanza << "to='#{xmlfrom}' " if xmlfrom
        stanza << "from='#{xmlto}' "
        stanza << "id='#{XML.uuid}' "
        stanza << "version='1.0'>"

        @sendq << stanza.join('')

        if @state.include?(:sasl) and @state.include?(:tls)
            log(:debug, "TLS/SASL stream established")
        elsif @state == [:sasl]
            log(:debug, "SASL stream established")
        elsif @state == [:tls]
            log(:debug, "TLS stream established")
        elsif @state.empty?
            log(:debug, "stream established")
            return
        end
    end

    def send_features
        feat = XML.new_element('stream:features')

        tls  = XML.new_element('starttls', 'urn:ietf:params:xml:ns:xmpp-tls')
        tls.add_element('optional')

        sasl = XML.new_element('mechanisms', 'urn:ietf:params:xml:ns:xmpp-sasl')
        mech = XML.new_element('mechanism')
        mech.text = 'PLAIN'
        sasl << mech
        sasl << XML.new_element('required')

        bind = XML.new_element('bind', 'urn:ietf:params:xml:ns:xmpp-bind')
        bind << XML.new_element('required')

        feat << tls  unless @state.include?(:tls)
        feat << sasl unless @state.include?(:sasl)
        feat << bind unless @state.include?(:bind)

        @sendq << feat
    end

    def start_tls(xml)
        # Verify the namespace
        unless xml.namespace == 'urn:ietf:params:xml:ns:xmpp-tls'
            fai = XML.new_element('failure', 'urn:ietf:params:xml:ns:xmpp-tls')
            @sendq << fai

            self.dead = true

            return
        end

        @sendq << XML.new_element('proceed', 'urn:ietf:params:xml:ns:xmpp-tls')

        # Force a write of the sendq so that the client expects
        # the TLS handshake. The event loop breaks it otherwise. Hack :/
        write

        @eventq.post(:tls_callback)

        @eventq.handle(:tls_callback) do
            socket = OpenSSL::SSL::SSLSocket.new(@socket, Kintara.ssl_context)

            begin
                socket.accept
            rescue Exception => e
                log(:error, "TLS error: #{e}")

                fai = XML.new_element('failure',
                                      'urn:ietf:params:xml:ns:xmpp-tls')
                @sendq << fai

                self.dead = true
            else
                @socket = socket
                @state << :tls
            end
        end
    end

    # For now, we're only doing SASL PLAIN
    def authorize(xml)
        unless xml.attributes['mechanism'] == 'PLAIN'
            fai = XML.new_element('failure', 'urn:ietf:params:xml:ns:xmpp-sasl')
            fai << XML.new_element('invalid-mechanism')

            @sendq << fai

            self.dead = true

            return
        end

        data = xml.text.unpack('m')[0]
        authzid, authcid, passwd = data.split("\000")
        authzid = authcid if authzid.empty?
        passwd  = Digest::MD5.hexdigest(passwd)

        node, domain = authzid.split('@')
        domain      ||= @connect_host

        user = DB::User.find(:node => node, :domain => domain)

        if not user or user.password != passwd
            fai = XML.new_element('failure', 'urn:ietf:params:xml:ns:xmpp-sasl')
            fai << XML.new_element('not-authorized')

            @sendq << fai

            self.dead = true
        else
            suc = XML.new_element('success', 'urn:ietf:params:xml:ns:xmpp-sasl')
            @sendq << suc

            @user = user
            @user.clients << self

            @state << :sasl
        end
    end

end # module Stream

end # module XMPP

