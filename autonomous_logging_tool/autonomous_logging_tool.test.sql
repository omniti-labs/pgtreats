select add_job('Job 1');
select * from job_log order by job_id; 

select add_step(1,'Step 1 For Job 1');
select * from job_log join job_detail using (job_id) order by job_id, step_id;

select upd_step(1,1,'OK','Update 1 For Step 1 For Job 1');
select * from job_log join job_detail using (job_id) order by job_id, step_id;

select add_step(1,'Step 2 For Job 1');
select * from job_log join job_detail using (job_id) order by job_id, step_id;

select upd_step(1,2,'','Update 1 For Step 2 For Job 1');
select * from job_log join job_detail using (job_id) order by job_id, step_id;

select upd_step(1,2,'','Update 2 For Step 2 For Job 1');
select * from job_log join job_detail using (job_id) order by job_id, step_id;

select upd_step(1,2,'OK','Update 3 For Step 2 For Job 1');
select * from job_log join job_detail using (job_id) order by job_id, step_id;

select close_job(1);
select * from job_log join job_detail using (job_id) order by job_id, step_id;


select add_job('Job 2');
select * from job_log order by job_id; 

select add_step(2,'Step 1 For Job 2');
select * from job_log join job_detail using (job_id) order by job_id, step_id;

select upd_step(2,1,'OK','Update 1 For Step 1 For Job 2');
select * from job_log join job_detail using (job_id) order by job_id, step_id;

select fail_job(2);
select * from job_log join job_detail using (job_id) order by job_id, step_id;
