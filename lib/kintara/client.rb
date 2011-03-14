#
# kintara: malkier xmpp server
# lib/kintara/client.rb: represents an XMPP client
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(document parsers/sax2parser).each { |m| require 'rexml/' + m }
%w(digest/md5 openssl).each { |m| require m }

# Import required application modules
%w(iq loggable stanza stream).each { |m| require 'kintara/' + m }

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

class Resource
    attr_accessor :client, :priority
    attr_reader   :name

    def initialize(name)
        @name     = name # The textual name
        @client   = nil  # The XMPP::Client that bound us
        @priority = 0    # Numeric priority
    end
end

class Client
    # Add the logging methods
    include Loggable

    # Add methods for stanza processing
    include XMPP::StanzaProcessor

    # Add methods for stream initialization
    include XMPP::Stream

    # Add methods for IQ stanza processing
    include XMPP::IQProcessor

    ##
    # instance attributes
    attr_reader :host, :resource, :socket

    # A simple Exception class
    class Error < Exception
    end

    ##
    # XXX
    def initialize(host, socket)
        # The hostname our client connected to
        @connect_host = nil

        # Is our socket dead?
        @dead = false

        # Our event queue
        @eventq = EventQueue.new

        # Our hostname
        @host = host

        # Our Logger object
        @logger     = nil
        self.logger = nil

        # Our Parser object
        @parser = REXML::Parsers::SAX2Parser.new('')

        # Received data waiting to be parsed
        @recvq = ''

        # Our XMPP::Resource object
        @resource = nil

        # Data waiting to be sent
        @sendq = []

        # Our socket
        @socket = socket

        # Our connection state
        # Either empty, or an array => :tls, :sasl, :bind
        @state = []

        # Our DB user object
        @user = nil

        # The current XML stanza we're parsing
        @xml = nil

        # If we have a block let it set up our instance attributes
        yield(self) if block_given?

        @logger.progname = "#@host"

        # Set up event handlers
        set_default_handlers

        # Initialize the parser
        initialize_parser

        log(:debug, "new client from #@host")

        self
    end

    #######
    private
    #######

    def set_default_handlers
        @eventq.handle(:recvq_ready) { parse }

        @eventq.handle(:stanza_ready)    { |xml| process_stanza(xml)     }
        @eventq.handle(:new_stream)      { |xml| process_new_stream(xml) }
        @eventq.handle(:iq_stanza_ready) { |xml| process_iq(xml)         }
    end

    def initialize_parser
        @parser.listen(:start_element) do |uri, localname, qname, attributes|
            e = REXML::Element.new(qname)
            e.add_attributes(attributes)

            @xml = @xml.nil? ? e : @xml.add_element(e)

            # <stream:stream> never ends, so we have to do this manually
            if @xml.name == 'stream' and @state.length < 3
                @eventq.post(:new_stream, @xml)
                @xml = nil
            end
        end

        @parser.listen(:end_element) do |uri, localname, qname|
            # </stream:stream> is a special case
            if qname == 'stream:stream' and @xml.nil?
                @sendq << "</stream:stream>"
                self.dead = true
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
                stream_error('xml-not-well-formed')
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

            log(:info, "client from #@host disconnected")

            @socket.close
            @socket = nil
            @dead   = true
            @state  = []
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
            ret = @socket.read_nonblock(8192)
        rescue IO::WaitReadable
            retry
        rescue Exception => e
            ret = nil
        end

        if not ret or ret.empty?
            log(:info, "error from #@host: #{e}") if e
            self.dead = true
            return
        end

        string = ''
        string += "(#{@resource.name}) " if @resource
        string += '-> '
        string += ret.gsub("\n", '')
        log(:debug, string)

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
        # Use shift because we need it to fall off immediately
        while stanza = @sendq.shift
            begin
                @socket.write_nonblock(stanza.to_s)
            rescue IO::WaitReadable
                retry
            rescue Exception => e
                log(:info, "write error on #@host: #{e}")
                @sendq = []
                self.dead = true
                return
            else
                if @resource
                    log(:debug, "(#{@resource.name}) <- #{stanza.to_s}")
                else
                    log(:debug, "<- #{stanza.to_s}")
                end
            end
        end
    end
end

end # module XMPP

