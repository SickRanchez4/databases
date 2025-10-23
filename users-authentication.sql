-- ===================================================================
--			DATABASE: USERS & AUTHENTICATION (SQL Server)
-- ===================================================================

-- Roles Table
CREATE TABLE roles (
    id INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(50) UNIQUE NOT NULL,
    description NVARCHAR(MAX),
    created_at DATETIME DEFAULT GETDATE()
);

-- Users Table
CREATE TABLE users (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    email NVARCHAR(255) UNIQUE NOT NULL,
	email_verified BIT DEFAULT 0 NOT NULL,
    password_hash NVARCHAR(255) NOT NULL,
    first_name NVARCHAR(100) NOT NULL,
    last_name NVARCHAR(100) NOT NULL,
    phone NVARCHAR(20),
    is_active BIT DEFAULT 1,
    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE()
);

-- Intermediate table Users-Roles (many-to-many)
CREATE TABLE user_roles (
    user_id UNIQUEIDENTIFIER NOT NULL,
    role_id INT NOT NULL,
    assigned_at DATETIME DEFAULT GETDATE(),
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
);

-- Addresses Table
CREATE TABLE addresses (
    id INT IDENTITY(1,1) PRIMARY KEY,
    user_id UNIQUEIDENTIFIER NOT NULL,
    address_type NVARCHAR(20) CHECK (address_type IN ('shipping', 'billing')),
    street NVARCHAR(255) NOT NULL,
    city NVARCHAR(100) NOT NULL,
    country NVARCHAR(100) NOT NULL,
    postal_code NVARCHAR(20) NOT NULL,
    is_default BIT DEFAULT 0,
    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes for optimization
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_addresses_user_id ON addresses(user_id);
CREATE INDEX idx_users_is_active ON users(is_active);

-- Trigger to updated_at in users
GO
CREATE TRIGGER trg_users_updated_at
ON users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE users
    SET updated_at = GETDATE()
    FROM users u
    INNER JOIN inserted i ON u.id = i.id;
END;
GO

-- Trigger to updated_at in addresses
CREATE TRIGGER trg_addresses_updated_at
ON addresses
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE addresses
    SET updated_at = GETDATE()
    FROM addresses a
    INNER JOIN inserted i ON a.id = i.id;
END;
GO

-- Initial role data
INSERT INTO roles (name, description) VALUES
('admin', 'System administrator with full access'),
('customer', 'Regular customer of the store');

-- Example user
DECLARE @admin_id UNIQUEIDENTIFIER = NEWID();
INSERT INTO users (id, email, password_hash, first_name, last_name) VALUES
(@admin_id, 'admin@ecommerce.com', '123456', 'Morty', 'Smith');

	-- Assign admin role to the sample user
	INSERT INTO user_roles (user_id, role_id)
	SELECT @admin_id, id FROM roles WHERE name = 'admin';
	GO

-- Useful view to get users with their roles
CREATE VIEW users_with_roles AS
SELECT 
    u.id,
    u.email,
    u.first_name,
    u.last_name,
    u.phone,
    u.is_active,
    u.created_at,
    (
        SELECT r.id AS role_id,
               r.name AS role_name,
               r.description AS role_description
        FROM user_roles ur
        INNER JOIN roles r ON ur.role_id = r.id
        WHERE ur.user_id = u.id
        FOR JSON PATH
    ) AS roles
FROM users u;
GO

-- Stored procedure to create user with role
CREATE PROCEDURE sp_create_user_with_role
    @email NVARCHAR(255),
    @password_hash NVARCHAR(255),
    @first_name NVARCHAR(100),
    @last_name NVARCHAR(100),
    @phone NVARCHAR(20) = NULL,
    @role_name NVARCHAR(50) = 'customer'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @user_id UNIQUEIDENTIFIER = NEWID();
    DECLARE @role_id INT;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Insert user
        INSERT INTO users (id, email, password_hash, first_name, last_name, phone)
        VALUES (@user_id, @email, @password_hash, @first_name, @last_name, @phone);
        
        -- Get role_id
        SELECT @role_id = id FROM roles WHERE name = @role_name;
        
        -- Assign role
        IF @role_id IS NOT NULL
        BEGIN
            INSERT INTO user_roles (user_id, role_id)
            VALUES (@user_id, @role_id);
        END
        
        COMMIT TRANSACTION;
        
        SELECT @user_id AS user_id, 'Usuario creado exitosamente' AS message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        THROW;
    END CATCH
END;
GO

-- Stored procedure to get user by email with roles
CREATE PROCEDURE sp_get_user_by_email
    @email NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        u.id,
        u.email,
        u.password_hash,
        u.first_name,
        u.last_name,
        u.phone,
        u.is_active,
        u.created_at,
        u.updated_at,
        (
            SELECT r.id, r.name, r.description
            FROM user_roles ur
            INNER JOIN roles r ON ur.role_id = r.id
            WHERE ur.user_id = u.id
            FOR JSON PATH
        ) AS roles
    FROM users u
    WHERE u.email = @email;
END;
GO

-- =====================================================
-- USEFUL QUERIES
-- =====================================================

 -- Create new user with role
 --EXEC sp_create_user_with_role 
 --    @email = 'cliente@ejemplo.com',
 --    @password_hash = '123456',
 --    @first_name = 'Juan',
 --    @last_name = 'Pérez',
 --    @phone = '+1234567890',
 --    @role_name = 'customer';


-- Get user by email with roles
-- EXEC sp_get_user_by_email @email = 'admin@ecommerce.com';

-- Get all users with their roles (using view)
-- SELECT * FROM users_with_roles;

-- Update user information
-- UPDATE users 
-- SET first_name = 'Nuevo Nombre', phone = '+9876543210'
-- WHERE email = 'usuario@ejemplo.com';

-- Add additional role to a user
-- INSERT INTO user_roles (user_id, role_id)
-- SELECT id, (SELECT id FROM roles WHERE name = 'vendor')
-- FROM users WHERE email = 'usuario@ejemplo.com';

-- Remove role from a user
-- DELETE FROM user_roles 
-- WHERE user_id = (SELECT id FROM users WHERE email = 'usuario@ejemplo.com')
-- AND role_id = (SELECT id FROM roles WHERE name = 'vendor');

-- Deactivate user
-- UPDATE users SET is_active = 0 WHERE email = 'usuario@ejemplo.com';

-- Activate user
-- UPDATE users SET is_active = 1 WHERE email = 'usuario@ejemplo.com';
