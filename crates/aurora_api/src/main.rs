// Copyright (C) 2024 V.J. De Chico
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#![feature(duration_constructors)]

use std::{env, time::Duration};

use axum::{http::Method, Router};
use sqlx::postgres::PgPoolOptions;
use state::OVTState;
use tokio::net::TcpListener;
use tower_http::cors::{Any, CorsLayer};

mod channels;
mod error;
mod flags;
mod guilds;
mod messages;
mod pubsub;
mod state;
mod token;
mod users;

#[tokio::main]
async fn main() {
    dotenvy::dotenv().unwrap();

    let db_connection_str = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:1234@localhost".to_string());

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(3))
        .connect(&db_connection_str)
        .await
        .expect("can't connect to database");

    let state = OVTState {
        pg: pool,
        key: env::var("JWT_SECRET_KEY").unwrap(),
    };

    let cors = CorsLayer::new()
        .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::PATCH])
        .allow_headers(Any)
        .allow_origin(Any);

    let app = Router::new()
        .merge(users::router())
        .merge(guilds::router())
        .merge(channels::router())
        .merge(messages::router())
        .layer(cors)
        .with_state(state);

    let listener = TcpListener::bind("0.0.0.0:24635").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
