

<h1><a class='u' href='#TOP' title='click to go to top of document'
name="NAME"
>NAME</a></h1>

<p>pgsniff - Dump info about queries as they happen</p>

<h1><a class='u' href='#TOP' title='click to go to top of document'
name="SYNOPSIS"
>SYNOPSIS</a></h1>

<pre>  pgsniff &lt; -d interface | -f filename &gt;
          [ -l &lt;filename&gt; ] [ --hist ]
          [ -n &lt;cnt&gt; ] [ -t &lt;cnt&gt; ] [-pg]
          [ --inflight &lt;port&gt; ]
          [ BPF filter syntax ]</pre>

<h1><a class='u' href='#TOP' title='click to go to top of document'
name="DESCRIPTION"
>DESCRIPTION</a></h1>

<p>This tool will analyze either live packet streams or post-mortem packet dumps to extract PostgreSQL session information. It will track the client&lt;-&gt;server communication and reveal information about client requests (queries, prepares, etc.) and various metadata and statistics.</p>

<p>This tool was derived from the fine work of Max Maischein on <code>Sniffer::HTTP</code>.</p>

<dl>
<dt><a name="-d_&lt;interface&gt;"
>-d &lt;interface&gt;</a></dt>

<dd>
<p>Specifies a network <code>interface</code> for live packet capture. This option is not allowed in combination with -f.</p>

<dt><a name="-f_&lt;filename&gt;"
>-f &lt;filename&gt;</a></dt>

<dd>
<p>Specifies the <code>filename</code> of a pcap file dump (output of tcpdump). This option is not allowed in combination with -d.</p>

<dt><a name="-l_&lt;filename&gt;"
>-l &lt;filename&gt;</a></dt>

<dd>
<p>Write the witnessed queries out to the specified <code>filename</code>. If &#34;-&#34; is specified, standard output is used. If omitted, not log file is generated.</p>

<dt><a name="-pg"
>-pg</a></dt>

<dd>
<p>If writing a log file (see -l), use a logging format that looks like PostgreSQL&#39;s native query logging format to allow easy consumption by other PostgreSQL log processing tools.</p>

<dt><a name="--hist"
>--hist</a></dt>

<dd>
<p>Generate a historgram of time spent and tuples returned from each query sorted by total cummulative execution time. This can be limited using the -t option.</p>

<dt><a name="-t_&lt;cnt&gt;"
>-t &lt;cnt&gt;</a></dt>

<dd>
<p>Limit the histogram (--hist) output to the top <code>cnt</code> most time comsuming queries. If omitted, all queries are displayed.</p>

<dt><a name="-n_&lt;cnt&gt;"
>-n &lt;cnt&gt;</a></dt>

<dd>
<p>If specified, stop the program after <code>cnt</code> queries can been witnessed.</p>

<dt><a name="--inflight_&lt;port&gt;"
>--inflight &lt;port&gt;</a></dt>

<dd>
<p>By default, the system will only consider newly established postgresql client connections (those that progress through a normal TCP handshake). If this option is specified, it will attempt to start analyzing TCP sessions that are currently &#34;in flight&#34; by noticing packets targeted at the specified destination tcp <code>port</code>.</p>
</dd>
</dl>

<p>An optional BPF filter string may be specified to limit the packet capture output. If not specified, the default BPF filter is &#34;port 5432&#34;</p>

<h1><a class='u' href='#TOP' title='click to go to top of document'
name="LICENSE"
>LICENSE</a></h1>

<p>Copyright (c) 2010 OmniTI Computer Consulting, Inc.</p>

<p>Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:</p>

<pre>  1. Redistributions of source code must retain the above
     copyright notice, this list of conditions and the following
     disclaimer.
  2. Redistributions in binary form must reproduce the above
     copyright notice, this list of conditions and the following
     disclaimer in the documentation and/or other materials provided
     with the distribution.</pre>

<p>THIS SOFTWARE IS PROVIDED BY THE AUTHOR &#34;AS IS&#34; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, HETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.</p>
