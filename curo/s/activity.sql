-- Current activity
\! $HOME/.curo/c/watch $HOME/.curo/s/activity/query.1.sql ~/.curo/s/activity/fifo "Current activity"
\i ~/.curo/s/activity/fifo
\! rm -f ~/.curo/s/activity/fifo
\! clear
