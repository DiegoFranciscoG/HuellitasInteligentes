package com.huellitas.camara;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * Mensaje de señalización WebRTC (oferta, respuesta o candidato ICE)
 * intercambiado entre el visor y la cámara a través de WebSocket/STOMP para
 * establecer la conexión de video en vivo.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class WebRtcMessage {
    private String target;
    private String from;
    private JsonNode payload; // Can be offer, answer, or candidate JSON

    public String getTarget() {
        return target;
    }

    public void setTarget(String target) {
        this.target = target;
    }

    public String getFrom() {
        return from;
    }

    public void setFrom(String from) {
        this.from = from;
    }

    public JsonNode getPayload() {
        return payload;
    }

    public void setPayload(JsonNode payload) {
        this.payload = payload;
    }
}
