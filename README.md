# TheService
 Windows service template, Delphi7, win-1251

This is a windows service which can run code from compatible DLL using a variety of timers and/or TCP/IP client requests.
To use this tool one must:
1) Provide compatible DLL (template and example are included) and any additional files/folders used by DLL.
2) Rename service executible as you see fit (exe name will be used as service name).
3) Set everything up (service, DLL and TCP/IP server) using %EXENAME%.ini file.
4) Install service

TheService.ini contains sample parameters and their description as well as other hints about setting everything up.

Payload (DLL and stuff) shoud have their own exception handling, errors and work events logging, and comply service abort requests.
Anyways Service will do theris best to handle any payload exceptions, payload work event logging, and ServiceManager requests 
handling (including working thread forcefull termination) to be stable and keep working.

Service run procedures from DLL by timers and/or by client request. Every procedure call is added to a queue.
User requests have priority in queue over timers. All timers and user requests without arguments poining to the same procedure are queued as one item.
User requests with equal parameters are queued as single item. User requests with different parameters are queued up separately.
Items from queue are executed one at a time in a separate worker thread, and are removed from queue before execution.
So it is possible to have a call queued while that same call is executed, but impossible to have same call queued multiple times.
Subsequent requests will be redirected to a single queued item.

Every client request is handled separately, client will recieve heartbeat while their request is queued/executed and call_result upon completion.
(client application template and example are included)

1) As a windows service this tool covers:
 - service installation/uninstallation;
 - windows service name and descpription;
 - windows event log messaging;
 - windows authentication;
 - novell(network) authentication;
 - rudimentary credentials encryption.

2) As a nice software piece it covers
 - work events and errors logging;
 - service autoupdate;
 - payload autoupdate;
 - COM initialization;
 - BDE initialization.

Client-server details:
 - WinSock TCP/IP;
 - Call any procedure from compatible DLL;
 - Supports passing any (reasonable) argument into procedure call;
 - Client can stay connected and recieve exit code from theri procedure;
 - Support any reasonable amount of simultaneously connected clients.

Supported timers:
 - List of fixed timestamps;
 - Wait fixed amount of time between calls;
 - Wait fixed amount of time between last call completion and next call.

Includes DLL and Client templates and examples