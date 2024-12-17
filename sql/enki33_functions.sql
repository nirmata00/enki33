-- 2. Funciones y Triggers  
CREATE OR REPLACE FUNCTION update_modified_at()  
RETURNS TRIGGER AS $$  
BEGIN  
    NEW.modified_at = CURRENT_TIMESTAMP;  
    RETURN NEW;  
END;  
$$ LANGUAGE plpgsql;  

-- Trigger para actualizar modified_at
CREATE TRIGGER set_recurring_transaction_modified_at
    BEFORE UPDATE ON public.recurring_transaction
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at();

-- Trigger para actualizar fechas de próxima ejecución
CREATE TRIGGER update_recurring_dates
    BEFORE INSERT OR UPDATE ON public.recurring_transaction
    FOR EACH ROW
    EXECUTE FUNCTION update_recurring_transaction_dates();

-- Función para calcular la próxima fecha de pago  
CREATE OR REPLACE FUNCTION calculate_next_payment_date(  
    p_payment_day smallint,  
    p_current_date date DEFAULT CURRENT_DATE  
)  
RETURNS date AS $$  
DECLARE  
    v_next_date date;  
BEGIN  
    v_next_date := date_trunc('month', p_current_date) + (p_payment_day - 1) * interval '1 day';  

    IF v_next_date <= p_current_date THEN  
        v_next_date := v_next_date + interval '1 month';  
    END IF;  

    IF extract(day from v_next_date) != p_payment_day THEN  
        v_next_date := date_trunc('month', v_next_date) + interval '1 month' - interval '1 day';  
    END IF;  

    RETURN v_next_date;  
END;  
$$ LANGUAGE plpgsql;  

-- Función para calcular la fecha de corte  
CREATE OR REPLACE FUNCTION calculate_cut_date(  
    p_cut_day smallint,  
    p_current_date date DEFAULT CURRENT_DATE  
)  
RETURNS date AS $$  
DECLARE  
    v_next_date date;  
BEGIN  
    v_next_date := date_trunc('month', p_current_date) + (p_cut_day - 1) * interval '1 day';  

    IF v_next_date <= p_current_date THEN  
        v_next_date := v_next_date + interval '1 month';  
    END IF;  

    IF extract(day from v_next_date) != p_cut_day THEN  
        v_next_date := date_trunc('month', v_next_date) + interval '1 month' - interval '1 day';  
    END IF;  

    RETURN v_next_date;  
END;  
$$ LANGUAGE plpgsql;  

-- Función para calcular la próxima fecha de ejecución de transacciones recurrentes  
CREATE OR REPLACE FUNCTION calculate_next_execution_date(  
    p_start_date date,  
    p_frequency interval,  
    p_execution_day smallint,  
    p_last_execution_date date DEFAULT NULL  
)  
RETURNS date AS $$  
DECLARE  
    v_next_date date;  
    v_base_date date;  
BEGIN  
    v_base_date := COALESCE(p_last_execution_date, p_start_date);  
    v_next_date := v_base_date + p_frequency;  

    IF p_execution_day IS NOT NULL THEN  
        v_next_date := date_trunc('month', v_next_date) + (p_execution_day - 1) * interval '1 day';  

        IF v_next_date <= v_base_date THEN  
            v_next_date := v_next_date + interval '1 month';  
        END IF;  

        IF extract(day from v_next_date) != p_execution_day THEN  
            v_next_date := date_trunc('month', v_next_date) + interval '1 month' - interval '1 day';  
        END IF;  
    END IF;  

    RETURN v_next_date;  
END;  
$$ LANGUAGE plpgsql;  

-- Trigger para actualizar fechas de cuenta  
CREATE OR REPLACE FUNCTION update_account_payment_dates()  
RETURNS TRIGGER AS $$  
DECLARE  
    v_account_type_code varchar(20);  
BEGIN  
    SELECT code INTO v_account_type_code  
    FROM account_type  
    WHERE id = NEW.account_type;  

    IF v_account_type_code IN ('CREDIT_CARD', 'LOAN') THEN  
        IF NEW.payment_day IS NOT NULL THEN  
            NEW.next_payment_date := calculate_next_payment_date(NEW.payment_day);  
        END IF;  

        IF v_account_type_code = 'LOAN' AND NEW.loan_start_date IS NOT NULL AND NEW.loan_term_months IS NOT NULL THEN  
            NEW.loan_end_date := NEW.loan_start_date + (NEW.loan_term_months * interval '1 month');  
        END IF;  
    END IF;  

    RETURN NEW;  
END;  
$$ LANGUAGE plpgsql;  

-- Función para actualizar fechas de transacciones recurrentes
CREATE OR REPLACE FUNCTION update_recurring_transaction_dates()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_recurrent THEN
        IF TG_OP = 'INSERT' THEN
            -- Para nueva transacción recurrente
            NEW.next_execution_date := calculate_next_execution_date(
                NEW.start_date,
                (SELECT interval_value FROM public.recurrence_frequency WHERE id = NEW.frequency_id),
                NEW.execution_day
            );
        ELSIF TG_OP = 'UPDATE' THEN
            -- Para transacción recurrente existente
            NEW.next_execution_date := calculate_next_execution_date(
                NEW.start_date,
                (SELECT interval_value FROM public.recurrence_frequency WHERE id = NEW.frequency_id),
                NEW.execution_day,
                NEW.date
            );
            NEW.execution_count := COALESCE(NEW.execution_count, 0) + 1;

            IF NEW.max_executions IS NOT NULL AND NEW.execution_count >= NEW.max_executions THEN
                NEW.recurrence_status := 'CANCELLED';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger para actualizar fechas recurrentes
DROP TRIGGER IF EXISTS update_recurring_dates ON public.transaction;
CREATE TRIGGER update_recurring_dates
    BEFORE INSERT OR UPDATE ON public.transaction
    FOR EACH ROW
    WHEN (NEW.is_recurrent = true)
    EXECUTE FUNCTION update_recurring_transaction_dates();

-- Función para refrescar el resumen del período  
CREATE OR REPLACE FUNCTION refresh_period_summary()  
RETURNS TRIGGER AS $$  
BEGIN  
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.period_summary;  
    RETURN NULL;  
END;  
$$ LANGUAGE plpgsql;  

-- Trigger function para mantener el histórico de cambios en subcategorías
CREATE OR REPLACE FUNCTION public.track_subcategory_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.category_id != NEW.category_id OR OLD.budget_jar_id != NEW.budget_jar_id) THEN
        INSERT INTO public.sub_category_history (
            sub_category_id,
            old_category_id,
            new_category_id,
            old_budget_jar_id,
            new_budget_jar_id,
            change_type
        ) VALUES (
            NEW.id,
            OLD.category_id,
            NEW.category_id,
            OLD.budget_jar_id,
            NEW.budget_jar_id,
            CASE 
                WHEN OLD.category_id != NEW.category_id AND OLD.budget_jar_id != NEW.budget_jar_id THEN 'BOTH'
                WHEN OLD.category_id != NEW.category_id THEN 'CATEGORY_CHANGE'
                ELSE 'JAR_CHANGE'
            END
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger para actualizar presupuestos cuando cambia el ingreso del período
CREATE OR REPLACE FUNCTION update_jar_budgets_for_period()
RETURNS TRIGGER AS $$
BEGIN
    -- Actualizar o insertar presupuestos para cada jarra
    INSERT INTO public.jar_period_budget (period_id, budget_jar_id, calculated_amount)
    SELECT 
        NEW.period_id,
        bj.id,
        (NEW.total_income * (bj.percentage / 100))::numeric(15,2)
    FROM public.budget_jar bj
    ON CONFLICT (period_id, budget_jar_id) 
    DO UPDATE SET 
        calculated_amount = (NEW.total_income * (budget_jar.percentage / 100))::numeric(15,2);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_period_status()
RETURNS TRIGGER AS $$
DECLARE
    v_period_id uuid;
    v_is_closed boolean;
BEGIN
    -- Obtener el período correspondiente a la fecha de la transacción
    SELECT id, is_closed INTO v_period_id, v_is_closed
    FROM public.period
    WHERE NEW.date BETWEEN from_date AND to_date;

    IF v_is_closed THEN
        RAISE EXCEPTION 'No se pueden modificar transacciones en un período cerrado';
    END IF;

    -- Asignar automáticamente la transacción al período
    INSERT INTO public.transaction_period (transaction, period)
    VALUES (NEW.id, v_period_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_jar_budget()
RETURNS TRIGGER AS $$
DECLARE
    v_jar_id uuid;
    v_period_id uuid;
    v_budget numeric(15,2);
    v_spent numeric(15,2);
BEGIN
    -- Solo validar gastos
    IF NOT NEW.is_expense THEN
        RETURN NEW;
    END IF;

    -- Obtener la jarra de la subcategoría
    SELECT budget_jar_id INTO v_jar_id
    FROM public.sub_category
    WHERE id = NEW.sub_category;

    -- Obtener el período
    SELECT id INTO v_period_id
    FROM public.period
    WHERE NEW.date BETWEEN from_date AND to_date;

    -- Obtener presupuesto asignado
    SELECT calculated_amount INTO v_budget
    FROM public.jar_period_budget
    WHERE budget_jar_id = v_jar_id AND period_id = v_period_id;

    -- Calcular gastos actuales
    SELECT COALESCE(SUM(t.amount), 0) INTO v_spent
    FROM public.transaction t
    JOIN public.sub_category sc ON t.sub_category = sc.id
    WHERE sc.budget_jar_id = v_jar_id
    AND t.is_expense = true
    AND t.id != NEW.id
    AND t.date BETWEEN (SELECT from_date FROM public.period WHERE id = v_period_id)
                   AND (SELECT to_date FROM public.period WHERE id = v_period_id);

    IF (v_spent + NEW.amount) > v_budget THEN
        RAISE EXCEPTION 'El gasto excede el presupuesto disponible en la jarra. Disponible: %, Gasto: %', 
            (v_budget - v_spent), NEW.amount;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION recalculate_period_totals(p_period_id uuid)
RETURNS void AS $$
BEGIN
    -- Actualizar period_income
    INSERT INTO public.period_income (period_id, total_income)
    SELECT 
        p_period_id,
        COALESCE(SUM(t.amount), 0) as total_income
    FROM public.transaction t
    JOIN public.transaction_period tp ON t.id = tp.transaction
    WHERE tp.period = p_period_id
    AND NOT t.is_expense
    ON CONFLICT (period_id) 
    DO UPDATE SET 
        total_income = EXCLUDED.total_income,
        modified_at = CURRENT_TIMESTAMP;

    -- Refrescar vista materializada
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.period_summary;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_transfer_transaction()
RETURNS TRIGGER AS $$
DECLARE
    v_transfer_type_id uuid;
BEGIN
    -- Obtener ID del tipo de transacción 'TRANSFERENCIA'
    SELECT id INTO v_transfer_type_id
    FROM public.transaction_type
    WHERE name = 'TRANSFERENCIA';

    -- Validar que las transferencias tengan cuenta origen y destino
    IF NEW.transaction_type = v_transfer_type_id THEN
        IF NEW.transfer_account_id IS NULL THEN
            RAISE EXCEPTION 'Las transferencias requieren una cuenta destino';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Aplicar triggers  
CREATE TRIGGER set_modified_at  
    BEFORE UPDATE ON public.account  
    FOR EACH ROW  
    EXECUTE FUNCTION update_modified_at();  

CREATE TRIGGER trigger_update_account_dates  
    BEFORE INSERT OR UPDATE ON public.account  
    FOR EACH ROW  
    EXECUTE FUNCTION update_account_payment_dates();  

 

CREATE TRIGGER trigger_refresh_period_summary  
    AFTER INSERT OR UPDATE OR DELETE ON public.transaction  
    FOR EACH STATEMENT  
    EXECUTE FUNCTION refresh_period_summary();  

CREATE TRIGGER track_balance_changes
AFTER UPDATE OF balance ON public.account
FOR EACH ROW
WHEN (OLD.balance IS DISTINCT FROM NEW.balance)
EXECUTE FUNCTION public.record_balance_change();

CREATE TRIGGER track_transaction_balance_changes
AFTER INSERT ON public.transaction
FOR EACH ROW
EXECUTE FUNCTION public.record_transaction_balance_change();

CREATE TRIGGER track_subcategory_changes_trigger
AFTER UPDATE ON public.sub_category
FOR EACH ROW
EXECUTE FUNCTION public.track_subcategory_changes();

CREATE TRIGGER update_jar_budgets_trigger
AFTER INSERT OR UPDATE ON public.period_income
FOR EACH ROW
EXECUTE FUNCTION update_jar_budgets_for_period();

CREATE TRIGGER check_period_status_trigger
AFTER INSERT OR UPDATE ON public.transaction
FOR EACH ROW
EXECUTE FUNCTION check_period_status();

CREATE TRIGGER validate_jar_budget_trigger
BEFORE INSERT OR UPDATE ON public.transaction
FOR EACH ROW
EXECUTE FUNCTION validate_jar_budget();

CREATE TRIGGER validate_transfer_transaction_trigger
BEFORE INSERT OR UPDATE ON public.transaction
FOR EACH ROW
EXECUTE FUNCTION validate_transfer_transaction();

-- Función para refrescar la vista materializada
CREATE OR REPLACE FUNCTION refresh_recurrent_variations()
RETURNS trigger AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.recurrent_transaction_variations;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger para actualizar la vista materializada
CREATE TRIGGER trigger_refresh_recurrent_variations
    AFTER INSERT OR UPDATE OR DELETE ON public.transaction
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_recurrent_variations();

-- Trigger para sincronizar con auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.app_user (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'avatar_url'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger que se ejecuta después de una inserción en auth.users
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

    -- Función para el trigger que registra los cambios
CREATE OR REPLACE FUNCTION log_transaction_changes()
RETURNS TRIGGER AS $$
BEGIN
    -- Cambio de moneda
    IF NEW.currency_id != OLD.currency_id THEN
        INSERT INTO public.transaction_history (
            transaction_id,
            change_type,
            old_currency_id,
            new_currency_id,
            user_id
        ) VALUES (
            NEW.id,
            'CURRENCY',
            OLD.currency_id,
            NEW.currency_id,
            NEW.user_id
        );
    END IF;

    -- Cambio de organización
    IF NEW.organization_id != OLD.organization_id THEN
        INSERT INTO public.transaction_history (
            transaction_id,
            change_type,
            old_organization_id,
            new_organization_id,
            user_id
        ) VALUES (
            NEW.id,
            'ORGANIZATION',
            OLD.organization_id,
            NEW.organization_id,
            NEW.user_id
        );
    END IF;

    -- Cambio de categoría
    IF NEW.category != OLD.category THEN
        INSERT INTO public.transaction_history (
            transaction_id,
            change_type,
            old_category_id,
            new_category_id,
            user_id
        ) VALUES (
            NEW.id,
            'CATEGORY',
            OLD.category,
            NEW.category,
            NEW.user_id
        );
    END IF;

    -- Cambio de subcategoría
    IF NEW.sub_category != OLD.sub_category THEN
        INSERT INTO public.transaction_history (
            transaction_id,
            change_type,
            old_subcategory_id,
            new_subcategory_id,
            user_id
        ) VALUES (
            NEW.id,
            'SUBCATEGORY',
            OLD.sub_category,
            NEW.sub_category,
            NEW.user_id
        );
    END IF;

    -- Cambio de cuenta
    IF NEW.account != OLD.account THEN
        INSERT INTO public.transaction_history (
            transaction_id,
            change_type,
            old_account_id,
            new_account_id,
            user_id
        ) VALUES (
            NEW.id,
            'ACCOUNT',
            OLD.account,
            NEW.account,
            NEW.user_id
        );
    END IF;

    -- Cambio de tipo de transacción
    IF NEW.transaction_type != OLD.transaction_type THEN
        INSERT INTO public.transaction_history (
            transaction_id,
            change_type,
            old_transaction_type_id,
            new_transaction_type_id,
            user_id
        ) VALUES (
            NEW.id,
            'TRANSACTION_TYPE',
            OLD.transaction_type,
            NEW.transaction_type,
            NEW.user_id
        );
    END IF;

    -- Cambio de medio de transacción
    IF NEW.transaction_medium != OLD.transaction_medium THEN
        INSERT INTO public.transaction_history (
            transaction_id,
            change_type,
            old_transaction_medium_id,
            new_transaction_medium_id,
            user_id
        ) VALUES (
            NEW.id,
            'TRANSACTION_MEDIUM',
            OLD.transaction_medium,
            NEW.transaction_medium,
            NEW.user_id
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el trigger
CREATE TRIGGER track_transaction_changes
    AFTER UPDATE ON public.transaction
    FOR EACH ROW
    EXECUTE FUNCTION log_transaction_changes();

-- Procedimiento para crear una transferencia
CREATE OR REPLACE PROCEDURE create_account_transfer(
    p_amount numeric(15,2),
    p_from_account_id uuid,
    p_to_account_id uuid,
    p_transfer_date date,
    p_user_id uuid,
    p_notes text DEFAULT NULL,
    p_exchange_rate numeric(20,6) DEFAULT 1.0
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_from_currency_id uuid;
    v_to_currency_id uuid;
    v_from_transaction_id uuid;
    v_to_transaction_id uuid;
    v_transfer_type_id uuid;
BEGIN
    -- Obtener las monedas de las cuentas
    SELECT currency_id INTO v_from_currency_id FROM public.account WHERE id = p_from_account_id;
    SELECT currency_id INTO v_to_currency_id FROM public.account WHERE id = p_to_account_id;
    
    -- Obtener el ID del tipo de transacción para transferencias
    SELECT id INTO v_transfer_type_id 
    FROM public.transaction_type 
    WHERE name = 'TRANSFER';

    -- Crear la transacción de salida
    INSERT INTO public.transaction (
        date,
        amount,
        currency_id,
        account,
        transaction_type,
        notes,
        is_expense,
        user_id
    ) VALUES (
        p_transfer_date,
        -p_amount,
        v_from_currency_id,
        p_from_account_id,
        v_transfer_type_id,
        COALESCE(p_notes, 'Transfer out to account: ' || p_to_account_id),
        true,
        p_user_id
    ) RETURNING id INTO v_from_transaction_id;

    -- Crear la transacción de entrada
    INSERT INTO public.transaction (
        date,
        amount,
        currency_id,
        account,
        transaction_type,
        notes,
        is_expense,
        user_id
    ) VALUES (
        p_transfer_date,
        p_amount * p_exchange_rate,
        v_to_currency_id,
        p_to_account_id,
        v_transfer_type_id,
        COALESCE(p_notes, 'Transfer in from account: ' || p_from_account_id),
        false,
        p_user_id
    ) RETURNING id INTO v_to_transaction_id;

    -- Registrar la transferencia
    INSERT INTO public.account_transfer (
        amount,
        from_account_id,
        to_account_id,
        from_transaction_id,
        to_transaction_id,
        transfer_date,
        exchange_rate,
        notes,
        user_id
    ) VALUES (
        p_amount,
        p_from_account_id,
        p_to_account_id,
        v_from_transaction_id,
        v_to_transaction_id,
        p_transfer_date,
        p_exchange_rate,
        p_notes,
        p_user_id
    );

EXCEPTION WHEN OTHERS THEN
    -- Si algo falla, eliminar las transacciones creadas
    IF v_from_transaction_id IS NOT NULL THEN
        DELETE FROM public.transaction WHERE id = v_from_transaction_id;
    END IF;
    IF v_to_transaction_id IS NOT NULL THEN
        DELETE FROM public.transaction WHERE id = v_to_transaction_id;
    END IF;
    RAISE;
END;
$$;