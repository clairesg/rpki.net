# The Publication Protocol

The publication protocol is really two separate client/server protocols,
between different parties. The first is a configuration protocol for an IRBE
to use to configure a publication engine, the second is the interface by which
authorized clients request publication of specific objects.

Much of the architecture of the publication protocol is borrowed from the
[left-right protocol][1]: like the left-right protocol, the publication
protocol uses CMS-wrapped XML over HTTP with the same eContentType OID and the
same HTTP content-type, and the overall style of the XML messages is very
similar to the left-right protocol. All operations allow an optional "tag"
attribute to allow batching.

The publication engine operates a single HTTP server which serves both of
these subprotocols. The two subprotocols share a single server port, but use
distinct URLs to allow demultiplexing.

## Publication control subprotocol

The control subprotocol reuses the message-passing design of the left-right
protocol. Configured objects support the "create", "set", "get", "list", and
"destroy" actions, or a subset thereof when the full set of actions doesn't
make sense.

### &lt;config/&gt; object

The &lt;config/&gt; object allows configuration of data that apply to the
entire publication server rather than a particular client.

There is exactly one &lt;config/&gt; object in the publication server, and it
only supports the "set" and "get" actions -- it cannot be created or
destroyed.

Payload data which can be configured in a &lt;config/&gt; object:

bpki_crl:: (element)

> This is the BPKI CRL used by the publication server when signing the CMS
wrapper on responses in the publication subprotocol. As the CRL must be
updated at regular intervals, it's not practical to restart the publication
server when the BPKI CRL needs to be updated. The BPKI model doesn't require
use of a BPKI CRL between the IRBE and the publication server, so we can use
the publication control subprotocol to update the BPKI CRL.

### &lt;client/&gt; object

The &lt;client/&gt; object represents one client authorized to use the
publication server.

The &lt;client/&gt; object supports the full set of "create", "set", "get",
"list", and "destroy" actions. Each client has a "client_handle" attribute,
which is used in responses and must be specified in "create", "set", "get", or
"destroy" actions.

Payload data which can be configured in a &lt;client/&gt; object:

base_uri:: (attribute)

> This is the base URI below which this client is allowed to publish data. The
publication server may impose additional constraints in the case of a child
publishing beneath its parent.

bpki_cert:: (element)

> BPKI CA certificate for this &lt;client/&gt;. This is used as part of the
certificate chain when validating incoming TLS and CMS messages. If the
bpki_glue certificate is in use (below), the bpki_cert certificate should be
issued by the bpki_glue certificate; otherwise, the bpki_cert certificate
should be issued by the publication engine's bpki_ta certificate.

bpki_glue:: (element)

> Another BPKI CA certificate for this &lt;client/&gt;, usually not needed.
Certain pathological cross-certification cases require a two-certificate chain
due to issuer name conflicts. If used, the bpki_glue certificate should be the
issuer of the bpki_cert certificate and should be issued by the publication
engine's bpki_ta certificate; if not needed, the bpki_glue certificate should
be left unset.

## Publication subprotocol

The publication subprotocol is structured somewhat differently from the
publication control protocol. Objects in the publication subprotocol represent
objects to be published or objects to be withdrawn from publication. Each kind
of object supports two actions: "publish" and "withdraw". In each case the XML
element representing hte object to be published or withdrawn has a "uri"
attribute which contains the publication URI. For "publish" actions, the XML
element body contains the DER object to be published, encoded in Base64; for
"withdraw" actions, the XML element body is empty.

In theory, the detailed access control for each kind of object might be
different. In practice, as of this writing, access control for all objects is
a simple check that the client's `base_uri` is a leading substring of the
publication URI. Details of why access control might need to become more
complicated are discussed in a later section.

### &lt;certificate/&gt; object

The &lt;certificate/&gt; object represents an RPKI certificate to be published
or withdrawn.

### &lt;crl/&gt; object

The &lt;crl/&gt; object represents an RPKI CRL to be published or withdrawn.

### &lt;manifest/&gt; object

The &lt;manifest/&gt; object represents an RPKI publication manifest to be
published or withdrawn.

Note that part of the reason for the batching support in the publication
protocol is because _every_ publication or withdrawal action requires a new
manifest, thus every publication or withdrawal action will involve at least
two objects.

### &lt;roa/&gt; object

The &lt;roa/&gt; object represents a ROA to be published or withdrawn.

## Error handling

Error in this protocol are handled at two levels.

Since all messages in this protocol are conveyed over HTTP connections, basic
errors are indicated via the HTTP response code. 4xx and 5xx responses
indicate that something bad happened. Errors that make it impossible to decode
a query or encode a response are handled in this way.

Where possible, errors will result in a &lt;report_error/&gt; message which
takes the place of the expected protocol response message.
&lt;report_error/&gt; messages are CMS-signed XML messages like the rest of
this protocol, and thus can be archived to provide an audit trail.

&lt;report_error/&gt; messages only appear in replies, never in queries. The
&lt;report_error/&gt; message can appear in both the control and publication
subprotocols.

The &lt;report_error/&gt; message includes an optional _tag_ attribute to
assist in matching the error with a particular query when using batching.

The error itself is conveyed in the `error_code` (attribute). The value of
this attribute is a token indicating the specific error that occurred. At
present this will be the name of a Python exception; the production version of
this protocol will nail down the allowed error tokens here, probably in the
RelaxNG schema.

The body of the &lt;report_error/&gt; element itself is an optional text
string; if present, this is debugging information. At present this capabilty
is not used, debugging information goes to syslog.

## Additional access control considerations

As detailed above, the publication protocol is trivially simple. This glosses
over two bits of potential complexity:

  * In the case where parent and child are sharing a repository, we'd like to nest child under parent, because testing has demonstrated that even on relatively slow hardware the delays involved in setting up separate rsync connections tend to dominate synchronization time for relying parties. 
  * The repository operator might also want to do some checks to assure itself that what it's about to allow the RPKI engine to publish is not dangerous toxic waste. 

The up-down protocol includes a mechanism by which a parent can suggest a
publication URI to each of its children. The children are not required to
accept this hint, and the children must make separate arrangements with the
repository operator (who might or might not be the same as the entity that
hosts the children's RPKI engine operations) to use the suggested publication
point, but if everything works out, this allows children to nest cleanly under
their parents publication points, which helps reduce synchronization time for
relying parties.

In this case, one could argue that the publication server is responsible for
preventing one of its clients (the child in the above description) from
stomping on data published by another of its clients (the parent in the above
description). This goes beyond the basic access check and requires the
publication server to determine whether the parent has given its consent for
the child to publish under the parent. Since the RPKI certificate profile
requires the child's publication point to be indicated in an SIA extension in
a certificate issued by the parent to the child, the publication engine can
infer this permission from the parent's issuance of a certificate to the
child. Since, by definition, the parent also uses this publication server,
this is an easy check, as the publication server should already have the
parent's certificate available by the time it needs to check the child's
certificate.

The previous paragraph only covers a "publish" action for a `<certificate/>`
object. For "publish" actions on other objects, the publication server would
need to trace permission back to the certificate issued by the parent; for
"withdraw" actions, the publication server would have to perform the same
checks it would perform for a "publish" action, using the current published
data before withdrawing it. The latter in turn implies an ordering constraint
on "withdraw" actions in order to preserve the data necessary for these access
control decisions; as this may prove impractical, the publication server may
probably need to make periodic sweeps over its published data looking for
orphaned objects, but that's probably a good idea anyway.

Note that, in this publication model, any agreement that the repository makes
to publish the RPKI engine's output is conditional upon the object to be
published passing whatever access control checks the publication server
imposes.

   [1]: #_.wiki.doc.RPKI.CA.Protocols.LeftRight

