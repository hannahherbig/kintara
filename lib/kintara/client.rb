#
# kintara: malkier xmpp server
# lib/kintara/client.rb: represents an XMPP client
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required application modules
%w(loggable).each { |m| require 'kintara/' + m }

module XMPP

class Client
    # Add the logging methods
    include Loggable

    ##
    # instance attributes
    attr_reader :host, :socket
    attr_writer :debug

    # A simple Exception class
    class Error < Exception
    end

    ##
    # XXX
    def initialize(host, socket)
        # Is our socket dead?
        @dead = false

        # Our hostname
        @host = host

        # Our Logger object
        self.logger = nil

        # Received data waiting to be parsed
        @recvq = []

        # Data waiting to be sent
        @sendq = []

        # Our socket
        @socket = socket

        # Our connection state (one of none, tls, sasl, connected)
        @state = :none

        # If we have a block let it set up our instance attributes
        yield(self) if block_given?

        @logger.progname = "#@host"

        debug("new client from #@host")

        self
    end

    #######
    private
    #######


    ######
    public
    ######

    def need_write?
        @sendq.empty? ? false : true
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
        rescue EOFError
            ret = nil
        end

        unless ret
            debug("client from #@host disconnected")
            @socket.close
            return
        end
        
        ret.chomp!
        
        debug("#{ret}")
        
        # XXX - echo server!
        @sendq << ret

        # This passes every "line" to our block, including the "\n"
        #ret.scan(/(.+\n?)/) do |line|
        #    line = line[0]

        #    # If the last line had no \n, add this one onto it.
        #    if @recvq[-1] and @recvq[-1][-1].chr != "\n"
        #        @recvq[-1] += line
        #    else
        #        @recvq << line
        #    end
        #end

        #if @recvq[-1] and @recvq[-1][-1].chr == "\n"
        #    @eventq.post(:recvq_ready)
        #end

        # XXX

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
