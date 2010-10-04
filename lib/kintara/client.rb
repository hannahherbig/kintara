#
# kintara: malkier xmpp server
# lib/kintara/client.rb: represents an XMPP client
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(document parsers/sax2parser).each { |m| require 'rexml/' + m }
%w(openssl).each { |m| require m }

# Import required application modules
%w(loggable stanza).each { |m| require 'kintara/' + m }

#
# This is kind of a hack.
# There's no way to change any of REXML's parser's sources, which
# I kind of need to do so I don't have to run this for every stanza.
#
class REXML::Source
    def buffer=(string)
        @buffer ||= ''
        @buffer  += string
    end
end

module XMPP

class Client
    # Add the logging methods
    include Loggable

    # Add stanza processing. This is separated for clarity.
    include XMPP::StanzaProcessor

    ##
    # instance attributes
    attr_reader :host, :resource, :socket
    attr_writer :debug

    # A simple Exception class
    class Error < Exception
    end

    ##
    # XXX
    def initialize(host, socket)
        # Is our socket dead?
        @dead = false

        # Our event queue
        @eventq = EventQueue.new

        # Our hostname
        @host = host

        # Our Logger object
        self.logger = nil

        # Our Parser object
        @parser = REXML::Parsers::SAX2Parser.new('')

        # Received data waiting to be parsed
        @recvq = ''

        # The name of our bound resource
        @resource = nil

        # Data waiting to be sent
        @sendq = []

        # Our socket
        @socket = socket

        # Our connection state
        # Either empty, or an array that can include :tls and :sasl
        @state = []

        # The current XML stanza we're parsing
        @xml = nil

        # If we have a block let it set up our instance attributes
        yield(self) if block_given?

        @logger.progname = "#@host"

        # Set up event handlers
        set_default_handlers

        # Initialize the parser
        initialize_parser

        debug("new client from #@host")

        self
    end

    #######
    private
    #######

    def set_default_handlers
        @eventq.handle(:recvq_ready)  { parse }
        @eventq.handle(:stanza_ready) { |xml| process_stanza(xml) }

        @eventq.handle(:new_stream)   { |xml| initialize_new_stream(xml) }
    end

    def initialize_parser
        @parser.listen(:start_element) do |uri, localname, qname, attributes|
            e = REXML::Element.new(qname)
            e.add_attributes(attributes)

            @xml = @xml.nil? ? e : @xml.add_element(e)

            # <stream:stream> never ends, so we have to do this manually
            if @xml.name == 'stream' and @state.length < 2
                @eventq.post(:new_stream, @xml)
                @xml = nil
            end
        end

        @parser.listen(:end_element) do |uri, localname, qname|
            # </stream:stream> is a special case
            if qname == 'stream:stream' and @xml.nil?
                # Die
            else
                @eventq.post(:stanza_ready, @xml) unless @xml.parent
                @xml = @xml.parent
            end
        end

        @parser.listen(:characters) do |text|
            if @xml
                t = REXML::Text.new(text.to_s, @xml.whitespace, nil, true)
                @xml.add(t)
            end
        end

        @parser.listen(:cdata) do |text|
            @xml.add(REXML::CData.new(texdt)) if @xml
        end
    end

    def parse
        begin
            @parser.source.buffer = @recvq
            @parser.parse
        rescue REXML::ParseException => e
            if e.message =~ /must not be bound/i # REXML bug - reported
                str = 'xmlns:xml="http://www.w3.org/XML/1998/namespace"'
                @recvq.gsub!(str, '')
                retry
            else
                # REXML throws this when it gets a partial stanza that's not
                # well-formed. The RFC wants us to be able to stitch together
                # partial stanzas and also to detect invalid XML, but it's
                # pretty much impossible to do both, which is widely
                # recognized in the XMPP community. So, instead, we die.
                # XXX - error
            end
        ensure
            @recvq = ''
        end
    end

    #
    # Takes care of setting some stuff when we die.
    # ---
    # bool:: +true+ or +false+
    # returns:: +nil+
    #
    def dead=(bool)
        if bool
            # Try to flush the sendq first. This is for errors and such.
            write unless @sendq.empty?

            debug("client for #@host is dead")

            @socket.close
            @socket = nil
            @dead   = true
            @state  = []
        end
    end

    def error(defined_condition)
        err = XML.new_element('stream:error')
        na  = XML.new_element(defined_condition,
                              'urn:ietf:params:xml:ns:xmpp-streams')
        err << na

        @sendq << err

        self.dead = true
    end

    def initialize_new_stream(xml)
        # Verify the namespaces
        unless xml.attributes['stream'] == 'http://etherx.jabber.org/streams'
            error('invalid-namespace')
            return
        end

        unless xml.attributes['xmlns'] == 'jabber:client'
            error('invalid-namespace')
            return
        end

        # Check the version
        unless xml.attributes['version'] == '1.0'
            error('unsupported-version')
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

        stanza << "<?xml version='1.0'?>"
        stanza << "<stream:stream "
        stanza << "xmlns='jabber:client' "
        stanza << "xmlns:stream='http://etherx.jabber.org/streams' "
        stanza << "xml:lang='en' "
        stanza << "to='#{xmlfrom}' " if xmlfrom
        stanza << "from='#{xmlto}' "
        stanza << "id='#{XML.new_id}' "
        stanza << "version='1.0'>"

        @sendq << stanza.join('')

        if @state.include?(:sasl) and @state.include?(:tls)
            debug("TLS/SASL stream established")
        elsif @state == [:sasl]
            debug("SASL stream established")
        elsif @state == [:tls]
            debug("TLS stream established")
        elsif @state.empty?
            debug("stream established")
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

        feat << tls  unless @state.include?(:tls)
        feat << sasl unless @state.include?(:sasl)

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
                debug("TLS error: #{e}")

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

    ######
    public
    ######

    def need_write?
        @sendq.empty? ? false : true
    end

    def has_events?
        @eventq.needs_ran?
    end

    def run_events
        @eventq.run
    end

    def dead?
        @dead
    end

    ##
    # Called when we're ready to read.
    # ---
    # returns:: +self+
    #
    def read
        begin
            ret = @socket.readpartial(8192)
        rescue Errno::EAGAIN
            retry
        rescue Exception => e
            ret = nil
        end

        if not ret or ret.empty?
            debug("error from #@host: #{e}") if e
            debug("client from #@host disconnected")
            self.dead = true
            return
        end

        string = ''
        string += "(#@resource) " if @resource
        string += ret.gsub("\n", '')
        debug(string)

        @recvq += ret

        @eventq.post(:recvq_ready)

        self
    end

    ##
    # Called when we're ready to write.
    # ---
    # returns:: +self+
    #
    def write
        begin
            # Use shift because we need it to fall off immediately
            while stanza = @sendq.shift
                debug(stanza.to_s)

                @socket.write(stanza.to_s)
            end
        rescue Errno::EAGAIN
            retry
        rescue Exception => e
            debug("write error on #@host: #{e}")
            debug("client from #@host disconnected")
            @sendq = []
            self.dead = true
            return
        end
    end
end

end # module XMPP

