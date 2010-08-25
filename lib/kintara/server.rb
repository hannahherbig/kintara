#
# kintara: malkier xmpp server
# lib/kintara/server.rb: the server class
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(logger socket).each { |m| require m }

# Import required application modules
%w(event loggable).each { |m| require 'kintara/' + m }

class XMPPServer
    # Add the logging methods.
    include Loggable

    ##
    # instance attributes
    attr_reader :socket
    attr_writer :port, :bind_to, :type, :debug

    # A simple Exception class for some errors
    class Error < Exception
    end

    ##
    # Creates a new XMPPServer that listens for client connections.
    # If given a block, it passes itself to the block for pretty
    # attribute setting.
    #
    def initialize
        # Is our socket dead?
        @dead = false

        # Our event queue
        @eventq = EventQueue.new

        # Our Logger object
        self.logger = Logger.new($stderr)

        # If we have a block let it set up our instance attributes
        yield(self) if block_given?

        @logger.progname = "#@bind_to:#@port"

        debug("new #@type server at #@bind_to:#@port")

        # Start up the listener
        begin
            if @bind_to == '*'
                @socket = TCPServer.new(@port)
            else
                @socket = TCPServer.new(@bind_to, @port)
            end
        rescue Exception => e
            log("#{Kintara::ME}: error acquiring socket for #@bind_to:#@port")
            raise
        else
            debug("#@type server successfully listening at #@bind_to:#@port")
        end

        # Set up event handlers
        set_default_handlers

        self
    end

    #######
    private
    #######

    ##
    # Sets up some default event handlers to track various states and such.
    # ---
    # returns:: +self+
    #
    def set_default_handlers
        @eventq.handle(:new_connection) { new_connection }
    end

    def new_connection
        newsock = @socket.accept_nonblock

        # This is to get around some silly IPv6 stuff.
        host = newsock.peeraddr[3].sub('::ffff:', '')

        # XXX - client object, etc
        debug("established new connection for #{host}")
    end

    ######
    public
    ######

    def dead?
        @dead
    end

    def io_loop
        loop do
            if dead? # XXX - restart listener, or handle as event...
                log("listener is dead")
                break
            end

            # Update the current time
            Kintara.time = Time.now.to_f

            # Run the event loop. These events will add IO, and possibly other
            # events, so we keep running until it's empty.
            @eventq.run while @eventq.needs_ran?

            readfds  = [@socket]
            writefds = []
            errorfds = []

            # XXX - add clients to readfds for waiting, writefds for sendq

            ret = IO.select(readfds, writefds, errorfds, 0)

            next unless ret
            next if ret[0].empty? # XXX

            # XXX - socket events
            ret[0].each do |s|
                @eventq.post(:new_connection) if s == @socket
            end
        end
    end
end
