#
# kintara: malkier xmpp server
# lib/kintara/client.rb: represents an XMPP client
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(document parsers/sax2parser).each { |m| require 'rexml/' + m }

# Import required application modules
%w(loggable).each { |m| require 'kintara/' + m }

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

        # Data waiting to be sent
        @sendq = []

        # Our socket
        @socket = socket

        # Our connection state (one of none, tls, sasl, connected)
        @state = :none

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
    end

    def initialize_parser
        @parser.listen(:start_element) do |uri, localname, qname, attributes|
            e = REXML::Element.new(qname)
            e.add_attributes(attributes)

            @xml = @xml.nil? ? e : @xml.add_element(e)
        end

        @parser.listen(:end_element) do |uri, localname, qname|
            @eventq.post(:stanza_ready, @xml) unless @xml.parent
            @xml = @xml.parent
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
                data.gsub!(str, '')
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

    def process_stanza(stanza)
        debug("processing: #{stanza}")
    end

    #
    # Takes care of setting some stuff when we die.
    # ---
    # bool:: +true+ or +false+
    # returns:: +nil+
    #
    def dead=(bool)
        if bool
            debug("client for #@host is dead")
            @dead   = true
            @socket = nil
            @state  = :none
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

        unless ret
            debug("error from #@host: #{e}") if e
            debug("client from #@host disconnected")
            @socket.close
            self.dead = true
            return
        end

        debug("#{ret}")

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
                debug(stanza)
                @socket.write(stanza)
            end
        rescue Errno::EAGAIN
            retry
        end
    end
end

end # module XMPP

