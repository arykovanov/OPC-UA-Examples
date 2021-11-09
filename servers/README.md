# Learn how to build OPC-UA Servers; a step-by-step guide.

The numbers below correspond with the example sub-directories. We
recommend starting with example one, which is started as follows:

```console
mako -l::1_start
```

See the
[Mako Server command line video tutorial](https://youtu.be/vwQ52ZC5RRg)
for more information on how to start the Mako Server.

1. How to set up an OPC-UA server in four lines of code.

2. How to configure the server.
   This example shows how to customize the server configuration,
   including listening port, network interface, endpoint URL, etc..

3. An introduction in how to browse OPC-UA nodes on the server side.
   The address space is represented by set of nodes with references
   between them. This example shows how to browse the nodes in the
   address space and how to print them using the
   [trace](https://realtimelogic.com/ba/doc/?url=lua.html#_G_trace)
   function.

4. An introduction in how to read attributes on the server side.
   Every node in the address space can include a set of attributes.
   The main attributes of node are: NodeID, BrowseName, Value, NodeClass, etc.

5. How to add your own nodes to the OPC-UA Address Space. An
   initialized server only includes the standard address space. An
   OPC-UA server typically requires additional nodes for representing
   a complex object such as machinery. This example shows how to add
   your own nodes with custom values.

6. How to update nodes in a running system.
   This example adds an int64 node to the address space, starts the
   server, and then increments the int64 node every second.

7. How to set up a read/write callback for a variable node.
   This example sets callback for a float variable node, starts the
   server. The callback will be called for each read and write 
   requests from the client.

8. A complete example of OPCUA server application with web interface