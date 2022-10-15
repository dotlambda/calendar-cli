#!/bin/bash

## TODO: all references to calendar-cli should be replaced with references to kal.  Work in progress!

set -e

########################################################################
## SETUP
########################################################################

for path in . .. ./tests ../tests
do
    setup="$path/_setup_alias"
    [ -f $setup  ] && source $setup
done

if [ -z "$RUNTESTSNOPAUSE" ]
then
    echo "tests.sh"
    echo
    echo "Generally, tests.sh should only be run directly if you know what you are doing"
    echo "You may want to use test_calendar-cli.sh instead"
    echo
    echo "This script will use the following commands to access a calendar server:"
    echo
    echo "$kal"
    echo "$calendar_cli"
    echo
    echo "This may work if you have configured a calendar server."
    echo "The tests will add and delete events and tasks."
    echo "Content from 2010-10 may be deleted"
    echo
    echo "Press enter or ctrl-C"
    read foo
fi

echo "## CLEANUP from earlier failed test runs, if any"

QUIET=true
for uid in $($calendar_cli calendar agenda --from-time=2010-10-09 --agenda-days=5 --event-template='{uid}') ; do calendar_cli calendar delete --event-uid=$uid ; done
calendar_cli todo --categories scripttest delete
unset QUIET

########################################################################
## TEST CODE FOLLOWS
########################################################################

echo "## EVENTS"

echo "## this is a very simple test script without advanced error handling"
echo "## if this test script doesn't output 'ALL TESTS COMPLETED!  YAY!' in the end, something went wrong"

echo "## Attempting to add an event at 2010-10-09 20:00:00, 2 hours duration"
kal add event 'testing testing' '2010-10-09 20:00:00+2h' 
uid=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
[ -n "$uid" ] || error "got no UID back"

echo "## Attempting to add an event at 2010-10-10 20:00:00, CET (1 hour duration is default), with description and non-ascii location"
kal add event 'testing testing' '2010-10-10 20:00:00+01:00' --set-description='this is a test calendar event' --set-location='Москва'
uid2=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
[ -n "$uid2" ] || error "got no UID back"

echo "## Attempting to add an event at 2010-10-11 20:00:00, CET, 3h duration"
kal add event 'testing testing' '2010-10-11 20:00:00+01:00+3h'
uid3=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
echo "## OK: Added the event, uid is $uid"

echo "## Taking out the agenda for 2010-10-09 + four days"
kal select --start=2010-10-09 --end=+4d --event list --template='{DESCRIPTION} {LOCATION}'
echo $output | { grep -q 'this is a test calendar event Москва' && echo "## OK: found the event" ; } || error "didn't find the event"

echo "## Taking out the agenda for 2010-10-10, with uid"
kal select --start=2010-10-10 --end=+1d --event list --template='{DTSTART.dt} {UID}'
echo $output | { grep -q $uid2 && echo "## OK: found the UID" ; } || error "didn't find the UID"

echo "## Deleting events with uid $uid $uid2 $uid3"
kal select --event --uid=$uid delete
kal select --event --uid=$uid2 delete
kal select --event --uid=$uid3 delete

echo "## Searching again for the deleted event"
kal select --event --start=2010-10-10 --end=+3d list
echo $output | { grep -q 'testing testing' && error "still found the event" ; } || echo "## OK: didn't find the event"

echo "## Adding a full day event"
kal add event 'whole day testing' '2010-10-10+4d' 
uid=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
[ -n "$uid" ] || error "got no UID back"

echo "## fetching the full day event, in ics format"
kal select --start=2010-10-13 --end=+1d --event list --ics

echo "$output" | grep -q "whole day" || error "could not find the event"
echo "$output" | grep -q "20101010" || error "could not find the date"
echo "$output" | grep -q "20101010T" && error "a supposed whole day event was found to be with the time of day"
echo "OK: found the event"

## saving the ics data
tmpfile=$(mktemp)
cat $outfile > $tmpfile

echo "## cleanup, delete it"
kal select --event --uid=$uid delete

echo "## Same, using kal add ics"
kal add ical --ical-file=$tmpfile
rm $tmpfile

kal select --event --start=2010-10-13 --end=2010-10-14 list --ics
echo "$output" | grep -q "whole day" || error "could not find the event"
echo "$output" | grep -q "20101010" || error "could not find the date"
echo "$output" | grep -q "20101010T" && error "a supposed whole day event was found to be with the time of day"
echo "$output" | grep UID
echo "OK: found the event"
echo "## cleanup, delete it"

kal select --event --uid=$uid delete

## TODO: PROCRASTINATING TIME ZONES.  Waiting for a release of the icalendar library that doesn't depend on pytz
if [ -n "" ]; then
echo "## testing timezone support"
echo "## Create a UTC event"
calendar_cli --timezone='UTC' calendar add '2010-10-09 12:00:00+10m' 'testevent with a UTC timezone'
uid=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
[ -n "$uid" ] || error "got no UID back"

echo "## fetching the UTC-event, as ical data"
calendar_cli --icalendar --timezone=UTC calendar agenda --from-time='2010-10-09 11:59' --agenda-mins=3
[ -n "$output" ] || error "failed to find the event that was just added"
echo "$output" | grep -q "20101009T120000Z" || error "failed to find the UTC timestamp.  Perhaps the server is yielding timezone data for the UTC timezone?  In that case, the assert in the test code should be adjusted"

echo "## cleanup, delete it"
calendar_cli calendar delete --event-uid=$uid

echo "## Create an event with a somewhat remote time zone, west of UTC"
calendar_cli --timezone='Brazil/DeNoronha' calendar add '2010-10-09 12:00:00+10m' 'testevent with a time zone west of UTC'
uid=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
[ -n "$uid" ] || error "got no UID back"

echo "## fetching the remote time zone event, as ical data"
calendar_cli --icalendar --timezone=UTC calendar agenda --from-time='2010-10-09 13:59' --agenda-mins=3
## zimbra changes Brazil/DeNoronha to America/Noronha.  Actually, the server may theoretically use arbitrary IDs for the timezones.
echo "$output" | grep -Eq "TZID=\"?[a-zA-Z/]*Noronha" || echo "$output" | grep -q "140000Z" ||
    error "failed to find the remote timezone"

echo "## fetching the remote time zone event, in UTC-time"
calendar_cli --timezone=UTC calendar agenda --from-time='2010-10-09 13:59' --agenda-mins=3 --event-template='{dtstart}'
[ "$output" == '2010-10-09 14:00 (Sat)' ] || error "expected dtstart to be 2010-10-09 14:00 (Sat)"

echo "## fetching the remote time zone event, in CET-time (UTC+2 with DST, and October is defined as summer in Oslo, weird)"
calendar_cli --timezone=Europe/Oslo calendar agenda --from-time='2010-10-09 15:59' --agenda-mins=3 --event-template='{dtstart}'
[ "$output" == '2010-10-09 16:00 (Sat)' ] || error "expected dtstart to be 2010-10-09 15:00 (Sat)"

echo "## cleanup, delete it"
calendar_cli calendar delete --event-uid=$uid
fi

echo "## TODOS / TASK LISTS"

echo "## Attempting to add a task with category 'scripttest'"
kal add todo --set-class=PRIVATE --set-category scripttest "edit this task"
uidtodo1=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
kal add todo --set-class=CONFIDENTIAL --set-category scripttest "edit this task2"
uidtodo2=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
kal add todo --set-class=PUBLIC "another task for testing sorting, offset and limit"
uidtodo3=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')

echo "## Listing out all tasks with category set to 'scripttest'"
kal select --todo --category scripttest list
[ $(echo "$output" | wc -l) == 2 ] || error "We found more or less or none of the two todo items we just added"


echo "## Sort order and limit.  CONFIDENTIAL class should come first.  Only one task should be returned"
kal select --todo --sort-key=CLASS --limit 1 list --template '{CLASS}'
echo "$output" | grep -q CONFIDENTIAL || error "Sorting does not work as expected"
echo "$output" | grep -q PRIVATE && error "Limit does not work as expected"
echo "## print-uid subcommand will print the uid of the first thing found"
kal select --todo --sort-key=CLASS print-uid
[ $output == $uidtodo2 ] || error "print-uid subcommand does not work"

kal select --todo --sort-key='class' --limit 2 list --template '{CLASS}'
[ $(echo "$output" | wc -l) == 2 ] && echo "## OK: limit=2 working"
echo "$output" | grep -q PRIVATE || error "Limit/sorting does not work as expected"

echo "## Offset.  PRIVATE should come in the middle"
kal select --todo --sort-key=class --limit 1 --offset 1 list --template '{CLASS}'
echo "$output" | grep -q PRIVATE || error "Offset does not work as expected"

echo "## Reverse order.  PUBLIC should come first"
kal select --todo --sort-key=-CLASS --limit 1 list --template '{CLASS}'
echo "$output" | grep -q PUBLIC || error "Reverse sort does not work as expected"

echo "## Templating.  The task without category should come first or last"
kal select --todo --sort-key='{CATEGORIES.cats[0]:?aaa?}' --limit 1 list --template '{SUMMARY}'
echo "$output" | grep -q 'another task' || error "sort by template not working as expected"
kal select --todo --sort-key='{CATEGORIES.cats[0]:?zzz?}' --limit 1 list --template '{SUMMARY}'
echo "$output" | grep -q 'another task' && error "sort by template not working as expected"

echo "## Utilizing two sort keys"
kal select --todo --sort-key='{CATEGORIES.cats[0]:?zzz?}' --sort-key=CLASS  --limit 1 list --template '{CLASS}'
[ "$output" == "CONFIDENTIAL" ] || error "two sort keys didn't work as expected"
kal select --todo --sort-key='{CATEGORIES.cats[0]:?zzz?}' --sort-key=-CLASS  --limit 1 list --template '{CLASS}'
[ "$output" == "PRIVATE" ] || error "two sort keys didn't work as expected"

echo "## Editing the task"
kal select --todo --category scripttest edit --set-summary "editing" --add-category "scripttest2"

## TODO: add tests for multiple sort keys

echo "## Verifying that the edits got through"
kal select --todo --category scripttest list
[ $(echo "$output" | wc -l) == 1 ] && echo "## OK: found the todo item we just edited and nothing more"
kal select --todo --category scripttest2 list
[ $(echo "$output" | wc -l) == 1 ] && echo "## OK: found the todo item we just edited and nothing more"
kal select --todo --category scripttest3 list
[ $(echo "$output" | wc -l) == 1 ] && echo "## OK: found the todo item we just edited and nothing more"
kal select --todo --comment editing list
[ $(echo "$output" | wc -l) == 1 ] && echo "## OK: found the todo item we just edited and nothing more"


echo "## Complete the task"
kal select --todo --category scripttest edit --complete
kal select --todo --category scripttest list
[ -z "$output" ] && echo "## OK: todo-item is done"
echo "## Test that we can list out completed tasks, and also undo completion"
kal select --todo --category scripttest --include-completed edit --uncomplete
kal select --todo --category scripttest list
[ -z "$output" ] && error "--uncomplete does not work!"
kal select --todo --uid $uidtodo1 --uid $uidtodo2 --uid $uidtodo3 delete --multi-delete

echo "## parent-child relationships"
echo "## Going to add three todo-items with children/parent relationships"
kal add todo --set-category scripttest "this is a grandparent"
uidtodo1=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
kal add todo  --set-category scripttest --set-parent $uidtodo1 "this is both a parent and a child"
uidtodo2=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
kal add todo --set-category scripttest --set-parent $uidtodo1 --set-parent $uidtodo2 "this task is a child of it's grandparent ... (what?)"
uidtodo3=$(echo $output | perl -ne '/uid=(.*)$/ && print $1')
kal select --todo --category scripttest list
[ $(echo "$output" | wc -l) == 3 ] && echo "## OK: found three tasks"
kal select --todo --category scripttest --skip-parents list
[ $(echo "$output" | wc -l) == 1 ] && echo "## OK: found only one task now"
kal select --todo --category scripttest --skip-children list
[ $(echo "$output" | wc -l) == 1 ] && echo "## OK: found only one task now"
echo "## Going to complete the grandchildren task"
kal select --todo --skip-parents --category scripttest edit --complete
kal select --todo --skip-parents --category scripttest list
[ $(echo "$output" | wc -l) == 1 ] && echo "## OK: found only one task now"
echo "## Going to complete the child task"
kal select --todo --skip-parents --category scripttest edit --complete
kal select --todo --skip-parents --category scripttest list
[ $(echo "$output" | wc -l) == 1 ] && echo "## OK: found only one task now"
echo "## Going to complete the grandparent task"
kal select --todo --skip-parents --category scripttest edit --complete
kal select --todo --skip-parents --category scripttest list
[ -z "$output" ] && echo "## OK: found no tasks now"
kal select --todo --category scripttest list
[ -z "$output" ] && echo "## OK: found no tasks now"

kal select --todo --uid $uidtodo1 --uid $uidtodo2 --uid $uidtodo3 delete --multi-delete

echo "## test completion of recurring task"
kal add todo --set-category=scripttest --set-rrule="FREQ=YEARLY;COUNT=2" "this is a yearly task to be performed twice"
uidtodo=$(echo "$output" | perl -ne '/uid=(.*)$/ && print $1')
kal select --todo list --template='{UID}'
## since no time range is given, the task cannot be expanded
[ "$output" == "$uidtodo" ] || error "weird problem"
echo "## completing it should efficiently move the due one year into the future"
kal select --todo complete
kal select --todo list --template='{DUE.dt:%F}'
echo "$output" | grep -q "$(date -d '+1 year' +%F)" || error "completion of event with RRULE did not go so well"
echo "## since count is set to two, completing it for the second time should complete the whole thing"
kal select --todo complete
[ -z "$output" ] && echo "## OK: found no tasks now"
kal select --todo --uid $uidtodo delete

echo "## test completion of recurring task with fixed occurance time"
kal add todo --set-category=scripttest --set-rrule='FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=1;BYHOUR=13;BYMINUTE=0;BYSECOND=0' "This task should be done next time 1st of January"
kal select --todo complete
kal select --todo list --template='{DUE.dt:%F}'
echo "$output" | grep -q "$(date -d '+1 year' +%Y)-01-01" || error "completion of event with RRULE did not go so well"

echo "## some kal TESTS COMPLETED SUCCESSFULLY!  YAY!"

rm $outfile

