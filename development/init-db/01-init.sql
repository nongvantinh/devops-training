-- Initialize database for CoffeeShop application
CREATE DATABASE IF NOT EXISTS coffeeshop;

-- Create user if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'coffeeshop_user') THEN
        CREATE USER coffeeshop_user WITH PASSWORD 'dev_password';
    END IF;
END
$$;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE coffeeshop TO coffeeshop_user;

-- Connect to coffeeshop database
\c coffeeshop;

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO coffeeshop_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO coffeeshop_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO coffeeshop_user;
