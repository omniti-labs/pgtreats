-- Current activity
\! $HOME/.curo/c/watch $HOME/.curo/s/activity/query.1.sql $HOME/.curo/s/activity/fifo "Current activity"
\i ~/.curo/s/activity/fifo
\! rm -f $HOME/.curo/s/activity/fifo
\! clear
