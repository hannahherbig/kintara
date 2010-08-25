#
# kintara: malkier xmpp server
# lib/kintara/server.rb: acts as a TCP server
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(logger socket).each { |m| require m }

# Import required application modules
%w(client event loggable).each { |m| require 'kintara/' + m }

module XMPP

# This class acts as a TCP server and handles all clients connected to it.
class Server
    # Add the logging methods
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
        # A list of our connected clients
        @clients = []

        # Is our socket dead?
        @dead = false

        # Our event queue
        @eventq = EventQueue.new

        # Our Logger object
        self.logger = nil

        # If we have a block let it set up our instance attributes
        yield(self) if block_given?

        @logger.progname = "#@bind_to:#@port"

        debug("new #@type server at #@bind_to:#@port")

        # Start up the listener
        start_listening

        # Set up event handlers
        set_default_handlers

        self
    end

    #######
    private
    #######

    def start_listening
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
            @dead = false
        end
    end

    ##
    # Sets up some default event handlers to track various states and such.
    # ---
    # returns:: +self+
    #
    def set_default_handlers
        @eventq.handle(:dead)       { start_listening }
        @eventq.handle(:connection) { new_connection  }

        @eventq.handle(:read_ready)  { |*args| client_read(*args)  }
        @eventq.handle(:write_ready) { |*args| client_write(*args) }
    end

    def new_connection
        newsock = @socket.accept_nonblock

        # This is to get around some silly IPv6 stuff
        host = newsock.peeraddr[3].sub('::ffff:', '')

        debug("established new connection for #{host}")

        @clients << XMPP::Client.new(host, newsock) do |c|
            c.logger = @logger
            c.debug  = @debug
        end
    end

    def client_read(socket)
        @clients.find { |client| client.socket == socket }.read
    end

    def client_write(socket)
        @clients.find { |client| client.socket == socket }.write
    end

    ######
    public
    ######

    def dead?
        @dead
    end

    def io_loop
        loop do
            # Update the current time
            Kintara.time = Time.now.to_f

            # Is our server's listening socket dead?
            if dead?
                debug("listener has died on #@host:#@port, restarting")
                @socket.close
                @socket = nil
                @eventq.post(:dead)
            end

            # Run the event loop. These events will add IO, and possibly other
            # events, so we keep running until it's empty.
            @eventq.run while @eventq.needs_ran?

            readfds  = [@socket]
            writefds = []

            @clients.each do |client|
                if client.need_write? # XXX (sendq has data)
                    writefds << client.socket
                else
                    readfds  << client.socket
                end
            end

            ret = IO.select(readfds, writefds, nil, 0)

            next unless ret

            # readfds
            ret[0].each do |socket|
                if socket == @socket
                    @eventq.post(:connection)
                else
                    @eventq.post(:read_ready, socket)
                end
            end unless ret[0].empty?

            # writefds
            ret[1].each do |socket|
                @eventq.post(:write_ready, socket)
            end unless ret[1].empty?
        end
    end
end

end # module XMPP