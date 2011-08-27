kintara -- malkier xmpp server
==============================

This application is free but copyrighted software; see `doc/license.txt`.

Information and repositories can be found on [GitHub][].

[github]: http://github.com/malkier/kintara/

This application requires the following to be installed:

  - ruby (>= 1.8.7, >= 1.9.2) (MRI and rbx known to work)
  - openssl
  - rake (`gem install --remote rake`)
  - sequel (`gem install --remote sequel`)

OpenSSL is required for TLS encrypted streams. Rake is required for unit tests
and package management. Sequel is required for database management. If you want
to run the tests, you'll also need bacon. Once all the dependencies are met,
edit `bin/kintara` to your liking and go!

TABLE OF CONTENTS
-----------------
  1. Credits
  2. Contact and Support
  3. References

1\. CREDITS
-----------

This is a clean, RFC-compliant XMPP server. It doesn't require a system-wide
installation making it suitable for shell servers. The server should happily
federate with any RFC-compliant servers supporting, at the very least, the
dialback protocol. The server's pretty strict about enforcing the RFC, with
minor exemptions for ancient servers.

This application is not based on any other code. One of my first large Ruby
applications was an XMPP server, but as I had just come from writing C I wasn't
very accustomed to Ruby and did it largely The Wrong Way. Trying to fix it to
do it The Ruby Way was very painful, and in the end I decided that after now
having many years of Ruby experience in a wide variety of fields I'd have
another go at it.

I don't particularly mean for this to be actively scalable, but that would be
nice. I don't really code much in my free time. I have a long-standing pain
problem and one technique I use to distract myself. Since coding demands most
if not all of your attention it helps take the focus on the pain away.

Any code in this application that isn't totally original came from my other
Ruby applications.

Currently, this application is totally written, tested, and mainted by me:

  - rakaur, Eric Will <rakaur@malkier.net>

As always, I extend special thanks to all of those within the XMPP community,
and especially stpeter for answering my endless questions about the RFCs:

  - stpeter, Peter Saint-Andre <stpeter@jabber.org>

2\. CONTACT AND SUPPORT
-----------------------

For bug or feature reports, please use GitHub's [issue tracking][1].

[1]: http://github.com/rakaur/kintara/issues/

If you're reporting a bug, please include information on how to reproduce the
problem. If you can't reproduce it there's probably nothing I can do. Be sure
to include Ruby's backtrace information if possible.

If your problem requires extensive debugging in a real-time situation, my JID
is rakaur@malkier.net. Alternatively, you can find me on irc.malkier.net.

If you've read this far, congratulations. You are among the few elite people
that actually read documentation. Thank you.

3\. REFERENCES
--------------

    [   XMPP-CORE] -- RFC 3920 -- XMPP: Core
    [     XMPP-IM] -- RFC 3921 -- XMPP: Instant Messaging and Presence
    [      BASE64] -- RFC 3548 -- The Base16, Base32, and Base64 Data Encodings
    [       PLAIN] -- RFC 4616 -- The PLAIN SASL Mechanism
    [  STRINGPREP] -- RFC 3454 -- Preparation of Internationalized Strings
    [         IDN] -- RFC 3491 -- Stringprep Profile for Domain Names
    [        SASL] -- RFC 2222 -- Simple Authentication and Security Layer
    [         SRV] -- RFC 2782 -- DNS RR SRV
    [         TLS] -- RFC 2246 -- Transport Layer Security
    [  IQ-VERSION] -- XEP 0092 -- Software Verson
    [       DISCO] -- XEP 0030 -- Service Discovery
    [  MSGOFFLINE] -- XEP 0160 -- Best Practices for Handling Offline Messages
    [       DELAY] -- XEP 0203 -- Delayed Delivery
    [ IQ-REGISTER] -- XEP 0077 -- In-Band Registration
    [  VCARD-TEMP] -- XEP 0054 -- vcard-temp
    [VCARD-AVATAR] -- XEP 0153 -- vCard-Based Avatar

