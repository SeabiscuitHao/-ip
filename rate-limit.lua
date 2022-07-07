local function close_redis(red)

    if not red then

        return

    end

    local pool_max_idle_time = 10000

    local pool_size = 100

    local ok, err = red:set_keepalive(pool_max_idle_tme, pool_size)

    if not ok then

        ngx.say("set keepalive err : ", err)

    end

end

local ip_block_time = 120 --封禁IP时间（秒）

local ip_time_out = 30    --指定ip访问频率时间段（秒）

local ip_max_count = 40 --指定ip访问频率计数最大值（秒）

local BUSINESS = "sqd-ratelimit" --nginx的location中定义的业务标识符

--连接redis

local redis = require "resty.redis"

local conn = redis:new()

ok, err = conn:connect("127.0.0.1", 6379)

conn:set_timeout(2000) --超时时间2秒

--连接失败 跳转到脚本结尾

if not ok then

    --goto FLAG

    close_redis(conn)

end

local count, err = conn:get_reused_times()

if 0 == count then

    ----新建连接 认证密码

    ok, err = conn:auth("yourredispassword")

    if not ok then

        ngx.say("failed to auth: ", err)

        return

    end

elseif err then

    ----从连接池中获取连接 无需再次认证密码

    return

end

--ip是否被禁止访问 存在则返回403

is_block, err = conn:get(BUSINESS .. "-BLOCK-" .. ngx.var.remote_addr)

if is_block == '1' then

    ngx.exit(429)

    close_redis(conn)

end

--查询ip计数器

ip_count, err = conn:get(BUSINESS .. "-COUNT-" .. ngx.var.remote_addr)

if ip_count == ngx.null then

    --如果不存在 将该IP存入redis 并将计数器设置为1 该KEY的超时时间为ip_time_out

    res, err = conn:set(BUSINESS .. "-COUNT-" .. ngx.var.remote_addr, 1)

    res, err = conn:expire(BUSINESS .. "-COUNT-" .. ngx.var.remote_addr, ip_time_out)

else

    if tonumber(ip_count) >= ip_max_count then

        --如果超过单位时间限制的访问次数，则添加限制访问标识，限制时间为ip_block_time

        res, err = conn:set(BUSINESS .. "-BLOCK-" .. ngx.var.remote_addr, 1)

        res, err = conn:expire(BUSINESS .. "-BLOCK-" .. ngx.var.remote_addr, ip_block_time)

    else

        res, err = conn:incr(BUSINESS .. "-COUNT-" .. ngx.var.remote_addr)

    end

end

-- 结束标记

local ok, err = conn:close()