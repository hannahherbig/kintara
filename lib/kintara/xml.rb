#
# kintara: malkier xmpp server
# lib/kintara/xml.rb: random XML generation, etc
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(rexml/document securerandom).each { |m| require m }

# Import required application modules
#%w().each { |m| require m }

module XML
    extend self

    def new_element(name, namespace = nil)
        elem = REXML::Element.new(name)
        elem.add_namespace(namespace) if namespace

        elem
    end

    XID_RE = /
             ^                # beginning of string
             (?:              # non-capturing group
                 ([^\s@\/]+)@ # anything-but-slash|@ followed by @
             )?               # close non-capturing, ? makes it optional
             ([^\s\/@]+)      # always grab anything-but-slash|@
             \/?              # optional slash
             (?:              # non-capturing group
                 ([^\s\/@]+)  # optional anything-but-slash|@
             )                # close non-capturing group
             $                # end of string
             /x

    def split_xid(xid)
        XID_RE.match(xid).captures
    end

    def valid_xid?(xid)
        XID_RE.match(xid)
    end

    #
    # Generate a unique id.
    #
    # return:: [String] random string
    #
    def uuid
        first  = SecureRandom.hex(4)
        second = SecureRandom.hex(2)
        third  = SecureRandom.hex(2)
        fourth = SecureRandom.hex(2)
        fifth  = SecureRandom.hex(6)

        "#{first}-#{second}-#{third}-#{fourth}-#{fifth}"
    end

end # module XML
