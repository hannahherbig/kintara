#
# kintara: malkier xmpp server
# lib/kintara/loggable.rb: a mixin for easy logging
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

module Loggable
    ##
    # Logs a regular message.
    # ---
    # message:: the string to log
    # returns:: +self+
    #
    def log(message)
        @logger.info(caller[0].split('/')[-1]) { message } if @logger
    end

    ##
    # Logs a debug message.
    # ---
    # message:: the string to log
    # returns:: +self+
    #
    def debug(message)
        return unless @logger

        @logger.debug(caller[0].split('/')[-1]) { message } if @debug
    end

    ##
    # Sets the logging object to use.
    # If it quacks like a Logger object, it should work.
    # ---
    # logger:: the Logger to use
    # returns:: +self+
    #
    def logger=(logger)
        @logger = logger

        # Set to false/nil to disable logging...
        return unless @logger

        @logger.datetime_format = '%m/%d %H:%M:%S '

        # We only have 'logging' and 'debugging', so just set the
        # object to show all levels. I might change this someday.
        @logger.level = Logger::DEBUG
    end
end # module Loggable
