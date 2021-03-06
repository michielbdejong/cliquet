import six
from pyramid import httpexceptions

from cliquet import logger
from cliquet.utils import Enum, json, reapply_cors


ERRORS = Enum(
    MISSING_AUTH_TOKEN=104,
    INVALID_AUTH_TOKEN=105,
    BADJSON=106,
    INVALID_PARAMETERS=107,
    MISSING_PARAMETERS=108,
    INVALID_POSTED_DATA=109,
    INVALID_RESOURCE_ID=110,
    MISSING_RESOURCE=111,
    MISSING_CONTENT_LENGTH=112,
    REQUEST_TOO_LARGE=113,
    MODIFIED_MEANWHILE=114,
    METHOD_NOT_ALLOWED=115,
    CLIENT_REACHED_CAPACITY=117,
    FORBIDDEN=121,
    CONSTRAINT_VIOLATED=122,
    UNDEFINED=999,
    BACKEND=201,
    SERVICE_DEPRECATED=202
)
"""Predefined errors as specified by the protocol.

+-------------+-------+------------------------------------------------+
| status code | errno | description                                    |
+-------------+-------+------------------------------------------------+
| 401         | 104   | Missing Authorization Token                    |
+-------------+-------+------------------------------------------------+
| 401         | 105   | Invalid Authorization Token                    |
+-------------+-------+------------------------------------------------+
| 400         | 106   | request body was not valid JSON                |
+-------------+-------+------------------------------------------------+
| 400         | 107   | invalid request parameter                      |
+-------------+-------+------------------------------------------------+
| 400         | 108   | missing request parameter                      |
+-------------+-------+------------------------------------------------+
| 400         | 109   | invalid posted data                            |
+-------------+-------+------------------------------------------------+
| 404         | 110   | Invalid Token / id                             |
+-------------+-------+------------------------------------------------+
| 404         | 111   | Missing Token / id                             |
+-------------+-------+------------------------------------------------+
| 411         | 112   | Content-Length header was not provided         |
+-------------+-------+------------------------------------------------+
| 413         | 113   | Request body too large                         |
+-------------+-------+------------------------------------------------+
| 412         | 114   | Resource was modified meanwhile                |
+-------------+-------+------------------------------------------------+
| 405         | 115   | Method not allowed on this end point           |
+-------------+-------+------------------------------------------------+
| 429         | 117   | Client has sent too many requests              |
+-------------+-------+------------------------------------------------+
| 403         | 121   | Resource's access forbidden for this user      |
+-------------+-------+------------------------------------------------+
| 409         | 122   | Another resource violates constraint           |
+-------------+-------+------------------------------------------------+
| 500         | 999   | Internal Server Error                          |
+-------------+-------+------------------------------------------------+
| 503         | 201   | Service Temporary unavailable due to high load |
+-------------+-------+------------------------------------------------+
| 410         | 202   | Service deprecated                             |
+-------------+-------+------------------------------------------------+
"""


def http_error(httpexception, errno=None,
               code=None, error=None, message=None, info=None):
    """Return a JSON formated response matching the error protocol.

    :param httpexception: Instance of :mod:`~pyramid:pyramid.httpexceptions`
    :param errno: stable application-level error number (e.g. 109)
    :param code: matches the HTTP status code (e.g 400)
    :param error: string description of error type (e.g. "Bad request")
    :param message: context information (e.g. "Invalid request parameters")
    :param info: additional details (e.g. URL to error details)
    :returns: the formatted response object
    :rtype: pyramid.httpexceptions.HTTPException
    """
    errno = errno or ERRORS.UNDEFINED

    # Track error number for request summary
    logger.bind(errno=errno)

    body = {
        "code": code or httpexception.code,
        "errno": errno,
        "error": error or httpexception.title
    }

    if message is not None:
        body['message'] = message

    if info is not None:
        body['info'] = info

    response = httpexception
    response.body = json.dumps(body).encode("utf-8")
    response.content_type = 'application/json'
    return response


def json_error_handler(errors):
    """Cornice JSON error handler, returning consistant JSON formatted errors
    from schema validation errors.

    This is meant to be used is custom services in your applications.

    .. code-block:: python

        upload = Service(name="upload", path='/upload',
                         error_handler=errors.json_error_handler)

    .. warning::

        Only the first error of the list is formatted in the response.
        (c.f. protocol).
    """
    assert len(errors) != 0
    sorted_errors = sorted(errors, key=lambda x: six.text_type(x['name']))
    error = sorted_errors[0]
    name = error['name']
    description = error['description']

    if name is not None:
        if name in description:
            message = description
        else:
            message = '%(name)s in %(location)s: %(description)s' % error
    else:
        message = '%(location)s: %(description)s' % error

    response = http_error(httpexceptions.HTTPBadRequest(),
                          errno=ERRORS.INVALID_PARAMETERS,
                          error='Invalid parameters',
                          message=message)
    response.status = errors.status
    response = reapply_cors(errors.request, response)
    return response


def raise_invalid(request, location='body', name=None, description=None,
                  **kwargs):
    """Helper to raise a validation error.

    :param location: location in request (e.g. ``'querystring'``)
    :param name: field name
    :param description: detailed description of validation error

    :raises: :class:`~pyramid:pyramid.httpexceptions.HTTPBadRequest`
    """
    request.errors.add(location, name, description, **kwargs)
    response = json_error_handler(request.errors)
    raise response
