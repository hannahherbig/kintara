#
# kintara: malkier xmpp server
# lib/kintara/config.rb: configuration DSL
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

require 'ostruct'

def configure(&block)
    Kintara.config = Kintara::Configuration.new
    Kintara.config.instance_eval(&block)
    Kintara.config.verify
    Kintara.new
end

class Kintara
    @@config = nil

    def Kintara.config; @@config; end
    def Kintara.config=(config); @@config = config; end

    class Configuration
        attr_reader :listeners, :log_level, :vhosts

        def initialize(&block)
            @listeners = []
            @log_level = :info
            @vhosts    = []
        end

        def verify
            # XXX
        end

        def logging(level)
            @log_level = level.to_s
        end

        def prep_listener(port, host = '*')
            listener         = OpenStruct.new
            listener.port    = port.to_i
            listener.bind_to = host.to_s

            listener
        end

        def listen_for_clients(*args)
            listener      = prep_listener(*args)
            listener.type = :c2s

            @listeners << listener
        end

        def listen_for_servers(*args)
            listener      = prep_listener(*args)
            listener.type = :s2s

            @listeners << listener
        end

        def virtual_hosts(&block)
            virtual_host(:all, &block)
        end

        def virtual_host(name, &block)
            vhost      = OpenStruct.new
            vhost.name = name

            vhost.extend(ConfigVirtualHost)
            vhost.instance_eval(&block)

            @vhosts << vhost
        end
    end

    module ConfigVirtualHost
        def ssl_certificate(certfile)
            self.ssl_certfile = certfile.to_s
        end

        def ssl_private_key(keyfile)
            self.ssl_keyfile = keyfile.to_s
        end

        def authorize(*args)
            args.each { |a| (self.authorized ||= []) << a }
        end

        def deny(*args)
            args.each { |d| (self.denied ||= []) << d }
        end

        def operator(name, opts = {})
            oper       = OpenStruct.new
            oper.name  = name.to_s
            oper.flags = opts[:flags]

            (self.operators ||= []) << oper
        end
    end
end
