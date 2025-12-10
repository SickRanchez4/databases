-- =============================================
-- TutorIA - Database Schema
-- SQL Server Database Design
-- =============================================

USE TutoriaDB;
GO

-- =============================================
-- TABLES
-- =============================================

-- Roles Table
IF OBJECT_ID('roles', 'U') IS NULL
CREATE TABLE roles (
    id INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(50) UNIQUE NOT NULL,
    created_at DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT chk_role_name CHECK (name IN ('admin', 'professor'))
);
GO

-- Users Table
IF OBJECT_ID('users', 'U') IS NULL
CREATE TABLE users (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    email NVARCHAR(255) UNIQUE NOT NULL,
    email_verified BIT DEFAULT 0 NOT NULL,
    password_hash NVARCHAR(255) NOT NULL,
    first_name NVARCHAR(100) NOT NULL,
    last_name NVARCHAR(100) NOT NULL,
    phone NVARCHAR(20) NOT NULL,
    is_active BIT DEFAULT 1 NOT NULL,
    created_at DATETIME2 DEFAULT SYSDATETIME(),
    updated_at DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT chk_email_format CHECK (email LIKE '%_@__%.__%')
);
GO

-- User-Roles Association (Many-to-Many)
IF OBJECT_ID('user_roles', 'U') IS NULL
CREATE TABLE user_roles (
    user_id UNIQUEIDENTIFIER NOT NULL,
    role_id INT NOT NULL,
    assigned_at DATETIME2 DEFAULT SYSDATETIME(),
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
);
GO

-- =============================================
-- INDEXES
-- =============================================

CREATE INDEX idx_users_email ON users(email) WHERE is_active = 1;
CREATE INDEX idx_users_active ON users(is_active);
CREATE INDEX idx_user_roles_user ON user_roles(user_id);
GO

-- =============================================
-- VIEWS
-- =============================================

CREATE OR ALTER VIEW vw_users_with_roles AS
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
               r.name AS role_name
        FROM user_roles ur
        INNER JOIN roles r ON ur.role_id = r.id
        WHERE ur.user_id = u.id
        FOR JSON PATH
    ) AS roles
FROM users u;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create user with role
CREATE OR ALTER PROCEDURE sp_crear_usuario_con_rol
    @email NVARCHAR(255),
    @password_hash NVARCHAR(255),
    @first_name NVARCHAR(100),
    @last_name NVARCHAR(100),
    @phone NVARCHAR(20),
    @role_name NVARCHAR(50) = 'professor'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @user_id UNIQUEIDENTIFIER = NEWID();
    DECLARE @role_id INT;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        INSERT INTO users (id, email, password_hash, first_name, last_name, phone)
        VALUES (@user_id, @email, @password_hash, @first_name, @last_name, @phone);
        
        SELECT @role_id = id FROM roles WHERE name = @role_name;
        
        IF @role_id IS NOT NULL
        BEGIN
            INSERT INTO user_roles (user_id, role_id)
            VALUES (@user_id, @role_id);
        END
        
        COMMIT TRANSACTION;
        
        SELECT @user_id AS user_id, 'Usuario creado exitosamente' AS mensaje;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- Update user profile
CREATE OR ALTER PROCEDURE sp_actualizar_usuario
    @user_id UNIQUEIDENTIFIER,
    @first_name NVARCHAR(100) = NULL,
    @last_name NVARCHAR(100) = NULL,
    @email NVARCHAR(255) = NULL,
    @phone NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE users
    SET 
        first_name = ISNULL(@first_name, first_name),
        last_name = ISNULL(@last_name, last_name),
        email = ISNULL(@email, email),
        phone = ISNULL(@phone, phone),
        updated_at = SYSDATETIME()
    WHERE id = @user_id;
    
    SELECT 'Usuario actualizado exitosamente' AS mensaje;
END;
GO

-- Get user by email
CREATE OR ALTER PROCEDURE sp_obtener_usuario_por_email
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
            SELECT r.id, r.name
            FROM user_roles ur
            INNER JOIN roles r ON ur.role_id = r.id
            WHERE ur.user_id = u.id
            FOR JSON PATH
        ) AS roles
    FROM users u
    WHERE u.email = @email AND u.is_active = 1;
END;
GO

-- =============================================
-- INITIAL DATA SEED
-- =============================================

-- Roles
IF NOT EXISTS (SELECT 1 FROM roles WHERE name = 'admin')
BEGIN
    INSERT INTO roles (name) VALUES
    ('admin'),
    ('professor');
END;
GO

-- Example users (CHANGE PASSWORDS IN PRODUCTION!)
DECLARE @admin_id UNIQUEIDENTIFIER = NEWID();
DECLARE @prof_id UNIQUEIDENTIFIER = NEWID();

IF NOT EXISTS (SELECT 1 FROM users WHERE email = 'admin@tutoria.edu')
BEGIN
    INSERT INTO users (id, email, password_hash, first_name, last_name, phone, email_verified)
    VALUES 
        (@admin_id, 'admin@tutoria.edu', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5UpfYVvBOqPZG', 'Admin', 'Sistema', '76543210', 1),
        (@prof_id, 'profesor@tutoria.edu', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5UpfYVvBOqPZG', 'Charles', 'Xavier', '76673578', 1);
    
    INSERT INTO user_roles (user_id, role_id)
    SELECT @admin_id, id FROM roles WHERE name = 'admin'
    UNION ALL
    SELECT @prof_id, id FROM roles WHERE name = 'professor';
END;
GO
