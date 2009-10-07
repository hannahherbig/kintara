#
# kintara: malkier xmpp server
# lib/kintara/server.rb: the server class.
#
# Copyright (c) 2004-2009 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules.
%w(logger socket).each { |m| require m }

# Import required kintara modules.
%w(kintara/loggable).each { |m| require m }

class XMPPServer
    # Add the logging methods.
    include Loggable

    ##
    # instance attributes
    attr_reader :socket
    attr_writer :port, :bind_to, :type, :debug

    ##
    # Creates a new XMPPServer that listens for client connections.
    # If given a block, it passes itself to the block for pretty
    # attribute setting.
    #
    def initialize
        # Is our socket dead?
        @dead = false

        # Our Logger object.
        self.logger = Logger.new($stderr)

        # If we have a block let it set up our instance attributes.
        yield(self) if block_given?

        @logger.progname = "#@bind_to:#@port"

        debug("new #{@type.to_s} server at #@bind_to:#@port")

        # Start up the listener.
        begin
            if @bind_to == '*'
                @socket = TCPServer.new(@port)
            else
                @socket = TCPServer.new(@bind_to, @port)
            end
        rescue Exception => e
            log("#{Kintara::ME}: error acquiring socket for #@bind_to:#@port")
            raise
        end

        self
    end

    ######
    public
    ######

    def io_loop
        sleep(10)
    end
end
