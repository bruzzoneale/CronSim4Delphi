# CronSim4Delphi

Cron Sim(ulator), a cron expression parser for Delphi 10+

This is a porting from CronSim for Python that you can find [Here](https://github.com/cuu508/cronsim.git) 

## Supported Cron Expression

CronSim supports Debian's cron implementation. You can find additional information in the original [CronSim Readme](https://github.com/cuu508/cronsim/blob/main/README.md)

To explain some cron expressions compatible with CronSim you can refer to this [on-line evaluator](https://crontab.cronhub.io/)

## Installation

Include CronSim.pas location in your Delphi's library path. 
The collection of helpers SCL.Types is required; you can find it [Here](https://github.com/bruzzoneale/delphi-scl)

## Usage

Simply create a new instance with TCronSim class:

```pascal
var cron := TCronSim.New('*/5 * * * *').StartAt(EncodeDateTime(2025,1,1, 9,0,0,0));
```

The *New* method creates a new instance and returns its interface, which does not need to be explicitly destroyed.

The *StartAt* method sets the starting day and time for evaluating the cron expression.

At this point, using the *Next* method, you can iterate over all occurrences where the condition of the cron expression is met.

```pascal
for var pass := 1 to 5 do
  writeln(cron.Next.ToStringFormat('dd/mm/yyyy  hh:nn:ss'));
```

Using for example the expression above, the output will be:

```
01/01/2025  09:05:00
01/01/2025  09:10:00
01/01/2025  09:15:00
01/01/2025  09:20:00
01/01/2025  09:25:00
```

alternatively you can iterate in reverse order:

```pascal
cron.Reversed;
```

the loop above produces:

```
01/01/2025  08:55:00
01/01/2025  08:50:00
01/01/2025  08:45:00
01/01/2025  08:40:00
01/01/2025  08:35:00
```

The sample program *test_cron* allows you to test different cron expressions.

The maximum period that can be processed is 50 years.

[![License](https://img.shields.io/badge/License-Apache%202.0-yellowgreen.svg)](https://opensource.org/licenses/Apache-2.0)
