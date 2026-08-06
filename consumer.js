/**
 * MQTT Consumer & Supabase Synchronizer
 * Proyecto: Vending Machine Productos de Limpieza (ESP32 Zephyr)
 * Autor: acovarrubiasd2500@alumno.ipn.mx
 */

require('dotenv').config();
const mqtt = require('mqtt');
const { createClient } = require('@supabase/supabase-js');

// Configuración de Supabase (requiere Service Role Key para escrituras automáticas)
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Error: SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY no están configurados en el archivo .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

// Configuración del Broker MQTT y Tópicos
const mqttBrokerHost = process.env.MQTT_BROKER_HOST || 'broker.hivemq.com';
const mqttBrokerPort = process.env.MQTT_BROKER_PORT || 1883;
const topicPrefix = process.env.MQTT_TOPIC_PREFIX !== undefined ? process.env.MQTT_TOPIC_PREFIX : 'vending'; // Prefijo para evitar colisiones en brokers públicos
const mqttUrl = `mqtt://${mqttBrokerHost}:${mqttBrokerPort}`;

console.log(`🔌 Conectando al broker MQTT en ${mqttUrl}...`);
const client = mqtt.connect(mqttUrl, {
  clientId: `supabase_consumer_${Math.random().toString(16).substring(2, 8)}`,
  clean: true,
  reconnectPeriod: 5000,
});

client.on('connect', () => {
  console.log('✅ Conectado exitosamente al broker MQTT.');

  // Suscribirse a los tópicos con prefijo del proyecto (ej. vending/VM001/income, vending/VM001/sales, etc.)
  const subTopics = [
    'income',
    'sales',
    'product',
    'actions',
    'money_collection',
    'alerts',
    'telemetry/security',
  ];

  const topics = subTopics.map((st) => (topicPrefix ? `${topicPrefix}/+/${st}` : `+/${st}`));

  topics.forEach((t) => {
    client.subscribe(t, (err) => {
      if (!err) {
        console.log(`📡 Suscrito al tópico: ${t}`);
      } else {
        console.error(`❌ Error al suscribirse a ${t}:`, err);
      }
    });
  });
});

client.on('message', async (topic, message) => {
  const payloadStr = message.toString();
  const parts = topic.split('/');

  let deviceId;
  let subTopic;

  if (topicPrefix && parts[0] === topicPrefix) {
    deviceId = parts[1];
    subTopic = parts.slice(2).join('/');
  } else if (!topicPrefix) {
    deviceId = parts[0];
    subTopic = parts.slice(1).join('/');
  } else {
    // Si viene de un tópico que no coincide con nuestro prefijo, lo ignoramos
    return;
  }

  if (!deviceId || !subTopic) {
    return;
  }

  // Intentar parsear el JSON de manera segura
  let data;
  try {
    data = JSON.parse(payloadStr);
  } catch (parseErr) {
    console.warn(`⚠️ Mensaje no JSON recibido en [${topic}]: "${payloadStr.substring(0, 50)}"`);
    return;
  }

  if (typeof data !== 'object' || data === null) {
    return;
  }

  try {
    // Obtener el ID interno de la máquina en Supabase
    let { data: machine } = await supabase
      .from('machines')
      .select('id')
      .eq('device_id', deviceId)
      .single();

    if (!machine) {
      // Si la máquina no existe en la BD, la registramos automáticamente
      const { data: newMachine, error: regErr } = await supabase
        .from('machines')
        .insert([{ device_id: deviceId, name: `Máquina Expendedora ${deviceId}` }])
        .select('id')
        .single();

      if (regErr) {
        console.error(`❌ Error registrando máquina ${deviceId}:`, regErr.message || regErr);
        return;
      }
      machine = newMachine;

      // Inicializar automáticamente los 8 tanques de la máquina
      const defaultTanks = Array.from({ length: 8 }, (_, i) => ({
        machine_id: machine.id,
        tank_number: i + 1,
        price_per_liter: 30.00,
        capacity_liters: 20.000,
        current_liters: 20.000,
        is_above_minimum: true,
      }));
      await supabase.from('machine_tanks').upsert(defaultTanks, { onConflict: 'machine_id,tank_number' });
    }

    const machineId = machine.id;

    // Helper para normalizar status enum ('success' / 'fail')
    const sanitizeStatus = (val) => {
      if (!val) return 'success';
      const s = val.toString().toLowerCase();
      if (['completed', 'success', 'ok', 'completed_success'].includes(s)) return 'success';
      return 'fail';
    };

    // Procesar según el tópico MQTT
    switch (subTopic) {
      case 'income': {
        // Pago por compra realizada
        const validTypes = ['monedas', 'efectivo', 'tarjeta'];
        const paymentType = validTypes.includes(data.type?.toLowerCase()) ? data.type.toLowerCase() : 'monedas';

        const { error } = await supabase.from('sale_incomes').insert([
          {
            machine_id: machineId,
            payment_type: paymentType,
            amount: data.amount ?? 0,
          },
        ]);
        if (error) {
          console.error(`❌ Error registrando ingreso en Supabase [${deviceId}]:`, error.message);
        } else {
          console.log(`💰 Ingreso registrado [${deviceId}]: $${data.amount} (${paymentType})`);
        }
        break;
      }

      case 'sales': {
        // Venta / surtido finalizado
        const statusEnum = sanitizeStatus(data.purchase_status || data.status);

        const { error } = await supabase.from('sales').insert([
          {
            machine_id: machineId,
            tank_number: data.tank,
            price_paid: data.price_paid,
            liters_purchased: data.liters_purchased,
            liters_flow_sensor: data.liters_flow_sensor,
            tank_liters_before: data.tank_liters_before,
            tank_liters_after: data.tank_liters_after,
            status: statusEnum,
          },
        ]);
        if (error) {
          console.error(`❌ Error registrando venta en Supabase [${deviceId}]:`, error.message);
        } else {
          console.log(`🛒 Venta registrada [${deviceId}]: Tanque ${data.tank} - Status: ${statusEnum}`);
        }
        break;
      }

      case 'product': {
        // Actualización / Creación de stock en tanque
        const { error } = await supabase
          .from('machine_tanks')
          .upsert(
            [
              {
                machine_id: machineId,
                tank_number: data.tank,
                price_per_liter: 30.00,
                capacity_liters: 20.000,
                current_liters: data.liters,
                is_above_minimum: data.above_minimum ?? true,
                updated_at: new Date().toISOString(),
              },
            ],
            { onConflict: 'machine_id,tank_number' }
          );
        if (error) {
          console.error(`❌ Error actualizando/creando stock en Supabase [${deviceId}]:`, error.message);
        } else {
          console.log(`🛢️ Stock actualizado/creado [${deviceId}]: Tanque ${data.tank} -> ${data.liters} L`);
        }
        break;
      }

      case 'actions': {
        // Recarga o Purga de tanque
        const validActions = ['sale', 'refill', 'purge'];
        const opType = validActions.includes(data.operation_type?.toLowerCase()) ? data.operation_type.toLowerCase() : 'refill';

        const { error } = await supabase.from('tank_operations').insert([
          {
            machine_id: machineId,
            tank_number: data.tank,
            operation_type: opType,
            tank_liters_before: data.tank_liters_before,
            tank_liters_after: data.tank_liters_after,
          },
        ]);
        if (error) {
          console.error(`❌ Error registrando operación en Supabase [${deviceId}]:`, error.message);
        } else {
          console.log(`🔧 Operación registrada [${deviceId}]: ${opType} en Tanque ${data.tank}`);
        }
        break;
      }

      case 'money_collection': {
        // Retiro de monedas / Corte de caja
        const validTypes = ['monedas', 'efectivo', 'tarjeta'];
        const paymentType = validTypes.includes(data.type?.toLowerCase()) ? data.type.toLowerCase() : 'monedas';
        const statusEnum = sanitizeStatus(data.status);

        const { error } = await supabase.from('money_collections').insert([
          {
            machine_id: machineId,
            payment_type: paymentType,
            amount_collected: data.amount,
            status: statusEnum,
          },
        ]);
        if (error) {
          console.error(`❌ Error registrando corte de caja en Supabase [${deviceId}]:`, error.message);
        } else {
          console.log(`💵 Corte de caja [${deviceId}]: $${data.amount} - ${statusEnum}`);
        }
        break;
      }

      case 'alerts': {
        // Alertas e incidencias (Violación de caja, tilt, etc.)
        const validCategories = ['security', 'pump', 'sales', 'stock', 'module'];
        const cat = validCategories.includes(data.category?.toLowerCase()) ? data.category.toLowerCase() : 'security';

        const { error } = await supabase.from('system_alerts').insert([
          {
            machine_id: machineId,
            category: cat,
            alert_type: data.type || data.alert_type || 'UNKNOWN_ALERT',
            tank_number: data.tank || null,
            value_num1: data.value1 || null,
            value_num2: data.value2 || null,
            value_string: data.value_string || null,
          },
        ]);
        if (error) {
          console.error(`❌ Error registrando alerta en Supabase [${deviceId}]:`, error.message);
        } else {
          console.log(`🚨 ALERTA [${deviceId}]: ${data.type || data.alert_type || 'UNKNOWN'} (${cat})`);
        }
        break;
      }

      case 'telemetry/security': {
        // Snapshot de estado y saldo disponible sin reclamar
        const { error } = await supabase.from('machine_status').upsert([
          {
            machine_id: machineId,
            available_balance: data.available_balance || 0.0,
            door_open: data.door_open || false,
            coinbox_tampered: data.coinbox_tampered || false,
            tilt_detected: data.tilt_detected || false,
            last_keepalive_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          },
        ]);
        if (error) {
          console.error(`❌ Error actualizando telemetría en Supabase [${deviceId}]:`, error.message);
        } else {
          console.log(`📊 Telemetría/Saldo [${deviceId}]: Disponible = $${data.available_balance}`);
        }
        break;
      }
    }
  } catch (err) {
    console.error(`❌ Error procesando mensaje MQTT en ${topic}:`, err.message || err);
  }
});

client.on('error', (err) => {
  console.error('❌ Error de conexión MQTT:', err);
});
